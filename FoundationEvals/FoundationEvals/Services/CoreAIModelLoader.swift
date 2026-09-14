import CoreAILanguageModels
import Foundation
import FoundationModels

enum CoreAIModelLoadingError: LocalizedError, Equatable, Sendable {
    case resourcesPathRequired
    case resourcesFolderUnavailable(String)
    case resourcesPathIsNotFolder(String)
    case staleResourcesBookmark(String)
    case modelLoadFailed(path: String, message: String)

    var errorDescription: String? {
        switch self {
        case .resourcesPathRequired:
            "Choose a Core AI model resource folder before running the evaluation."
        case .resourcesFolderUnavailable(let path):
            "The Core AI model resource folder is unavailable at \(path). Choose it again."
        case .resourcesPathIsNotFolder(let path):
            "The selected Core AI model resource path is not a folder: \(path)."
        case .staleResourcesBookmark(let path):
            "Access to the Core AI model resource folder at \(path) has expired. Choose it again."
        case .modelLoadFailed(let path, let message):
            "Could not load the Core AI model resources at \(path): \(message)"
        }
    }
}

struct CoreAIModelLoadResult: Sendable {
    let model: CoreAILanguageModel
    let modelName: String
    let contextSize: Int
    let capabilities: LanguageModelCapabilities
    let estimatedSizeOnDiskBytes: Int?

    fileprivate let securityScopedAccess: CoreAISecurityScopedAccess
}

struct CoreAIModelDescriptor: Equatable, Sendable {
    let modelName: String
    let contextSize: Int
    let estimatedSizeOnDiskBytes: Int?
    let supportsVision: Bool
    let supportsGuidedGeneration: Bool
    let supportsReasoning: Bool
    let supportsToolCalling: Bool

    init(result: CoreAIModelLoadResult) {
        modelName = result.modelName
        contextSize = result.contextSize
        estimatedSizeOnDiskBytes = result.estimatedSizeOnDiskBytes
        supportsVision = result.capabilities.contains(.vision)
        supportsGuidedGeneration = result.capabilities.contains(.guidedGeneration)
        supportsReasoning = result.capabilities.contains(.reasoning)
        supportsToolCalling = result.capabilities.contains(.toolCalling)
    }
}

enum CoreAIModelControlStatus: Equatable, Sendable {
    case unconfigured
    case readyToLoad
    case loading
    case loaded(CoreAIModelDescriptor)
    case failed(String)
}

actor CoreAIModelLoader {
    static let shared = CoreAIModelLoader()

    struct ResourceStamp: Hashable, Sendable {
        let relativePath: String
        let modificationDate: Date?
        let fileSize: Int?
        let fileIdentifier: String?
    }

    private struct CacheKey: Hashable, Sendable {
        let resourceURL: URL
        let resourceFingerprint: [ResourceStamp]
    }

    private struct CachedModel: Sendable {
        let key: CacheKey
        let result: CoreAIModelLoadResult
    }

    private var cachedModel: CachedModel?
    private var latestRequestedKey: CacheKey?

    func load(configuration: EvaluationCoreAIConfiguration) async throws -> CoreAIModelLoadResult {
        try Task.checkCancellation()
        let resolved = try Self.resolveResources(configuration)
        let key: CacheKey
        do {
            key = try Self.cacheKey(for: resolved.url)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CoreAIModelLoadingError.modelLoadFailed(
                path: resolved.url.path(percentEncoded: false),
                message: "Could not inspect the model resource files: \(error.localizedDescription)"
            )
        }

        latestRequestedKey = key
        if let cachedModel, cachedModel.key == key {
            return cachedModel.result
        }

        // ponytail: keep loads caller-owned so cancelling one request cannot cancel another;
        // add ref-counted coalescing only if concurrent model loads become measurable.
        let task = Task(priority: .userInitiated) {
            do {
                let bundle = try LanguageBundle(at: resolved.url)
                let model = try await CoreAILanguageModel(
                    resourcesAt: resolved.url,
                    mode: .eager
                )
                return CoreAIModelLoadResult(
                    model: model,
                    modelName: bundle.name,
                    contextSize: bundle.maxContextLength,
                    capabilities: model.capabilities,
                    estimatedSizeOnDiskBytes: model.estimatedSizeOnDiskBytes,
                    securityScopedAccess: resolved.securityScopedAccess
                )
            } catch {
                if error is CancellationError || Task.isCancelled {
                    throw CancellationError()
                }
                throw CoreAIModelLoadingError.modelLoadFailed(
                    path: resolved.url.path(percentEncoded: false),
                    message: error.localizedDescription
                )
            }
        }

        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        if latestRequestedKey == key {
            cachedModel = CachedModel(key: key, result: result)
        }
        return result
    }

    private static func resolveResources(
        _ configuration: EvaluationCoreAIConfiguration
    ) throws -> (url: URL, securityScopedAccess: CoreAISecurityScopedAccess) {
        let trimmedPath = configuration.resourcesPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw CoreAIModelLoadingError.resourcesPathRequired
        }

        let url: URL
        if let bookmark = configuration.resourcesBookmark {
            var isStale = false
            do {
                url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            } catch {
                throw CoreAIModelLoadingError.staleResourcesBookmark(trimmedPath)
            }
            guard !isStale else {
                throw CoreAIModelLoadingError.staleResourcesBookmark(trimmedPath)
            }
        } else {
            let expandedPath = (trimmedPath as NSString).expandingTildeInPath
            url = URL(filePath: expandedPath, directoryHint: .isDirectory)
        }

        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let access = CoreAISecurityScopedAccess(url: canonicalURL)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory) else {
            throw CoreAIModelLoadingError.resourcesFolderUnavailable(trimmedPath)
        }
        guard isDirectory.boolValue else {
            throw CoreAIModelLoadingError.resourcesPathIsNotFolder(trimmedPath)
        }
        return (canonicalURL, access)
    }

    private static func cacheKey(for url: URL) throws -> CacheKey {
        return CacheKey(
            resourceURL: url,
            resourceFingerprint: try resourceFingerprint(for: url)
        )
    }

    nonisolated static func resourceFingerprint(for url: URL) throws -> [ResourceStamp] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .fileResourceIdentifierKey,
        ]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        let rootComponents = url.standardizedFileURL.pathComponents
        var fingerprint: [ResourceStamp] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            let relativePath = fileURL.standardizedFileURL.pathComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")
            fingerprint.append(ResourceStamp(
                relativePath: relativePath,
                modificationDate: values.contentModificationDate,
                fileSize: values.fileSize,
                fileIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
            ))
        }
        if let enumerationError { throw enumerationError }
        return fingerprint.sorted { $0.relativePath < $1.relativePath }
    }
}

fileprivate final class CoreAISecurityScopedAccess: @unchecked Sendable {
    private let url: URL
    private let isAccessing: Bool

    init(url: URL) {
        self.url = url
        self.isAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
