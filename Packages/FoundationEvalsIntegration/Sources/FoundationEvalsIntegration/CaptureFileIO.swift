import Darwin
import Foundation

public enum CaptureFileIOError: Error, Equatable, LocalizedError {
    case notRegularFile
    case tooLarge(maximumBytes: Int)
    case notInsideRoot
    case pathTraversal
    case symlinkRejected
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .notRegularFile: "Only regular files can be captured or imported."
        case .tooLarge(let maximum): "The file exceeds the \(maximum)-byte limit."
        case .notInsideRoot: "The path is outside the allowed directory."
        case .pathTraversal: "The path contains a traversal or absolute component."
        case .symlinkRejected: "Symbolic links and aliases are not allowed in capture bundles."
        case .io(let message): message
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
}
