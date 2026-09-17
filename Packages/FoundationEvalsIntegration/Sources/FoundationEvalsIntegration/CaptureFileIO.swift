import Darwin
import Foundation

public enum CaptureFileIOError: Error, Equatable, LocalizedError {
    case notRegularFile
    case tooLarge(maximumBytes: Int)
    case notInsideRoot
    case pathTraversal
    case symlinkRejected
    case io(String)
    case tooManyEntries
    case directoryTooDeep

    public var errorDescription: String? {
        switch self {
        case .notRegularFile: "Only regular files can be captured or imported."
        case .tooLarge(let maximum): "The file exceeds the \(maximum)-byte limit."
        case .notInsideRoot: "The path is outside the allowed directory."
        case .pathTraversal: "The path contains a traversal or absolute component."
        case .symlinkRejected: "Symbolic links and aliases are not allowed in capture bundles."
        case .io(let message): message
        case .tooManyEntries: "The selected folder contains too many files or directories."
        case .directoryTooDeep: "The selected folder is nested too deeply."
        }
    }
}

public enum CaptureFileIO {
    public static func relativePathComponents(_ path: String) throws -> [String] {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
            throw CaptureFileIOError.pathTraversal
        }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." && !$0.isEmpty }) else {
            throw CaptureFileIOError.pathTraversal
        }
        return parts
    }

    public static func resolvedMember(root: URL, relativePath: String) throws -> URL {
        let parts = try relativePathComponents(relativePath)
        var url = root.standardizedFileURL
        for part in parts {
            url.append(path: part, directoryHint: .notDirectory)
        }
        let standardized = url.standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard standardized.path == rootPath || standardized.path.hasPrefix(prefix) else {
            throw CaptureFileIOError.notInsideRoot
        }
        return standardized
    }

    public static func readRegularFileNoFollow(at url: URL, maximumBytes: Int) throws -> Data {
        let path = url.path
        let fd = path.withCString { pointer in
            open(pointer, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else {
            if errno == ELOOP { throw CaptureFileIOError.symlinkRejected }
            throw CaptureFileIOError.io("Could not open \(url.lastPathComponent).")
        }
        defer { close(fd) }
        var status = stat()
        guard fstat(fd, &status) == 0 else {
            throw CaptureFileIOError.io("Could not inspect \(url.lastPathComponent).")
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else {
            throw CaptureFileIOError.notRegularFile
        }
        let reported = Int(status.st_size)
        guard reported >= 0, reported <= maximumBytes else {
            throw CaptureFileIOError.tooLarge(maximumBytes: maximumBytes)
        }
        var data = Data()
        data.reserveCapacity(reported)
        let cap = maximumBytes == Int.max ? Int.max : maximumBytes + 1
        while data.count < cap {
            let remaining = cap - data.count
            let chunkSize = min(remaining, 64 * 1_024)
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            let readCount = buffer.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress, chunkSize)
            }
            if readCount == 0 { break }
            if readCount < 0 { throw CaptureFileIOError.io("Read failed for \(url.lastPathComponent).") }
            data.append(contentsOf: buffer.prefix(readCount))
        }
        guard data.count <= maximumBytes else {
            throw CaptureFileIOError.tooLarge(maximumBytes: maximumBytes)
        }
        return data
    }

    public static func writeAtomically(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.moveItem(at: temporary, to: url)
            } else {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }
    }

    public static func openDirectoryNoFollow(at url: URL) throws -> Int32 {
        let fd = url.path.withCString { pointer in
            open(pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else {
            if errno == ELOOP { throw CaptureFileIOError.symlinkRejected }
            throw CaptureFileIOError.io("Could not open \(url.lastPathComponent).")
        }
        var status = stat()
        guard fstat(fd, &status) == 0, (status.st_mode & S_IFMT) == S_IFDIR else {
            close(fd)
            throw CaptureFileIOError.notRegularFile
        }
        return fd
    }

    public static func directoryNames(from directoryFD: Int32) throws -> [String] {
        let cloned = dup(directoryFD)
        guard cloned >= 0, let dir = fdopendir(cloned) else {
            if cloned >= 0 { close(cloned) }
            throw CaptureFileIOError.io("Could not list the selected folder.")
        }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
            }
            if name == "." || name == ".." || name.hasPrefix(".") { continue }
            names.append(name)
        }
        return names.sorted()
    }

    public static func openMemberNoFollow(directoryFD: Int32, name: String, directory: Bool) throws -> Int32 {
        let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (directory ? O_DIRECTORY : 0)
        let fd = name.withCString { pointer in
            openat(directoryFD, pointer, flags)
        }
        guard fd >= 0 else {
            if errno == ELOOP { throw CaptureFileIOError.symlinkRejected }
            throw CaptureFileIOError.io("Could not open \(name).")
        }
        var status = stat()
        guard fstat(fd, &status) == 0 else {
            close(fd)
            throw CaptureFileIOError.io("Could not inspect \(name).")
        }
        let type = status.st_mode & S_IFMT
        if directory {
            guard type == S_IFDIR else {
                close(fd)
                throw CaptureFileIOError.notRegularFile
            }
        } else {
            guard type == S_IFREG else {
                close(fd)
                throw CaptureFileIOError.notRegularFile
            }
        }
        return fd
    }

    public static func readRegularFileNoFollow(fromFileFD fd: Int32, maximumBytes: Int, name: String) throws -> Data {
        var status = stat()
        guard fstat(fd, &status) == 0 else {
            throw CaptureFileIOError.io("Could not inspect \(name).")
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else {
            throw CaptureFileIOError.notRegularFile
        }
        let reported = Int(status.st_size)
        guard reported >= 0, reported <= maximumBytes else {
            throw CaptureFileIOError.tooLarge(maximumBytes: maximumBytes)
        }
        var data = Data()
        data.reserveCapacity(reported)
        let cap = maximumBytes == Int.max ? Int.max : maximumBytes + 1
        while data.count < cap {
            let remaining = cap - data.count
            let chunkSize = min(remaining, 64 * 1_024)
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            let readCount = buffer.withUnsafeMutableBytes { pointer in
                Darwin.read(fd, pointer.baseAddress, chunkSize)
            }
            if readCount == 0 { break }
            if readCount < 0 { throw CaptureFileIOError.io("Read failed for \(name).") }
            data.append(contentsOf: buffer.prefix(readCount))
        }
        guard data.count <= maximumBytes else {
            throw CaptureFileIOError.tooLarge(maximumBytes: maximumBytes)
        }
        return data
    }
}
