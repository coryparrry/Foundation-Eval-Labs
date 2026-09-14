import Foundation

enum EvaluationAttachmentStorage {
    nonisolated static func readImportFile(
        at url: URL,
        isImage: Bool,
        maximumBytes: Int
    ) throws -> Data {
        guard url.isFileURL else { throw ImportError.notRegularLocalFile }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw ImportError.notRegularLocalFile
        }
        guard let byteCount = values.fileSize else {
            throw ImportError.unknownFileSize
        }
        guard byteCount <= maximumBytes else {
            throw isImage
                ? ImportError.imageTooLarge
                : ImportError.fileTooLarge
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        data.reserveCapacity(min(byteCount, maximumBytes))
        while data.count <= maximumBytes {
            let remaining = maximumBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(remaining, 64 * 1_024)),
                  !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= maximumBytes else {
            throw isImage
                ? ImportError.imageTooLarge
                : ImportError.fileTooLarge
        }
        return data
    }

    nonisolated static func storedFileURL(
        filename: String,
        attachmentID: UUID,
        in directory: URL
    ) throws -> URL {
        let storedIdentity = UUID(uuidString: (filename as NSString).deletingPathExtension)
        guard !filename.isEmpty,
              filename != ".",
              filename != "..",
              storedIdentity == attachmentID,
              !filename.contains("/"),
              !filename.contains("\\"),
              filename.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              (filename as NSString).lastPathComponent == filename else {
            throw EvaluationStoreError.persistence("Attachment storage contains an invalid filename.")
        }

        let standardizedDirectory = directory.standardizedFileURL
        let canonicalDirectory = standardizedDirectory.resolvingSymlinksInPath()
        let candidate = standardizedDirectory
            .appending(path: filename, directoryHint: .notDirectory)
            .standardizedFileURL
        let canonicalCandidate = candidate.resolvingSymlinksInPath()
        let fileManager = FileManager.default
        guard candidate.deletingLastPathComponent().path == standardizedDirectory.path,
              canonicalCandidate.deletingLastPathComponent().path == canonicalDirectory.path,
              (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw EvaluationStoreError.persistence("Attachment storage points outside its private directory.")
        }
        if fileManager.fileExists(atPath: candidate.path),
           try candidate.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile != true {
            throw EvaluationStoreError.persistence("Attachment storage is not a regular file.")
        }
        return candidate
    }
}

enum ImportError: LocalizedError {
    case tooManyFiles
    case tooManyImages
    case imageTooLarge
    case fileTooLarge
    case unknownFileSize
    case notRegularLocalFile
    case invalidFilename
    case unsupportedType
    case typeMismatch
    case unreadableImage
    case unreadablePDF
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .tooManyFiles: "A suite can attach up to 20 files."
        case .tooManyImages: "A suite can attach up to four images."
        case .imageTooLarge: "Images must be 10 MB or smaller."
        case .fileTooLarge: "Text and PDF files must be 5 MB or smaller."
        case .unknownFileSize: "The selected file size could not be determined."
        case .notRegularLocalFile: "Only regular local files can be imported."
        case .invalidFilename: "Attachment names must be plain filenames without path components."
        case .unsupportedType: "Attachments must be UTF-8 text, JSON, CSV, PDF, or an image."
        case .typeMismatch: "The declared media type does not match the filename extension."
        case .unreadableImage: "The image data could not be decoded."
        case .unreadablePDF: "The PDF contains no extractable text."
        case .notUTF8: "Text files must use UTF-8 encoding."
        }
    }
}
