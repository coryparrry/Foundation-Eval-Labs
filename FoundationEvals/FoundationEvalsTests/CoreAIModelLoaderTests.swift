import Foundation
import FoundationModels
import CoreAILanguageModels
import Testing
@testable import FoundationEvals

struct CoreAIModelLoaderTests {
    @Test func configurationDefaultsAndPersistsResourcePath() throws {
        var configuration = EvaluationCoreAIConfiguration()
        #expect(!configuration.hasResources)

        configuration.resourcesPath = "/Models/Test Model"
        let restored = try JSONDecoder().decode(
            EvaluationCoreAIConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        #expect(restored == configuration)
        #expect(restored.hasResources)
    }

    @Test func editingResourcePathInvalidatesBookmark() {
        var configuration = EvaluationCoreAIConfiguration(
            resourcesPath: "/Models/Old",
            resourcesBookmark: Data([1, 2, 3])
        )

        configuration.resourcesPath = "/Models/New"

        #expect(configuration.resourcesBookmark == nil)
    }

    @Test func loaderRejectsEmptyAndMissingResourcePaths() async {
        let loader = CoreAIModelLoader()

        await #expect(throws: CoreAIModelLoadingError.resourcesPathRequired) {
            try await loader.load(configuration: EvaluationCoreAIConfiguration())
        }

        let missingPath = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .path
        await #expect(
            throws: CoreAIModelLoadingError.resourcesFolderUnavailable(missingPath)
        ) {
            try await loader.load(
                configuration: EvaluationCoreAIConfiguration(resourcesPath: missingPath)
            )
        }
    }

    @Test func loaderRejectsAFileInsteadOfAResourceFolder() async throws {
        let directory = try coreAITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "metadata.json", directoryHint: .notDirectory)
        try Data("{}".utf8).write(to: file)
        let loader = CoreAIModelLoader()

        await #expect(
            throws: CoreAIModelLoadingError.resourcesPathIsNotFolder(file.path)
        ) {
            try await loader.load(
                configuration: EvaluationCoreAIConfiguration(resourcesPath: file.path)
            )
        }
    }

    @Test func malformedResourceFolderSurfacesTheModelLoadingFailure() async throws {
        let directory = try coreAITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not valid JSON".utf8).write(
            to: directory.appending(path: "metadata.json", directoryHint: .notDirectory)
        )
        let loader = CoreAIModelLoader()

        do {
            _ = try await loader.load(
                configuration: EvaluationCoreAIConfiguration(resourcesPath: directory.path)
            )
            Issue.record("Expected malformed Core AI resources to fail loading")
        } catch let error as CoreAIModelLoadingError {
            guard case .modelLoadFailed(let path, let message) = error else {
                Issue.record("Expected a modelLoadFailed error, got \(error)")
                return
            }
            #expect(URL(fileURLWithPath: path).standardizedFileURL.path == directory.standardizedFileURL.path)
            #expect(!message.isEmpty)
            #expect(error.localizedDescription.contains(directory.path))
        } catch {
            Issue.record("Expected CoreAIModelLoadingError, got \(error)")
        }
    }

    @Test func cacheFingerprintChangesWhenAModelAssetChanges() throws {
        let directory = try coreAITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let metadataURL = directory.appending(path: "metadata.json", directoryHint: .notDirectory)
        let assetURL = directory.appending(path: "weights.bin", directoryHint: .notDirectory)
        try Data("{}".utf8).write(to: metadataURL)
        try Data([0, 1, 2, 3]).write(to: assetURL)
        let fixedMetadataDate = Date(timeIntervalSinceReferenceDate: 1_000)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedMetadataDate],
            ofItemAtPath: metadataURL.path
        )

        let first = try CoreAIModelLoader.resourceFingerprint(for: directory)
        #expect(try CoreAIModelLoader.resourceFingerprint(for: directory) == first)
        try Data([3, 2, 1, 0]).write(to: assetURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceReferenceDate: 2_000)],
            ofItemAtPath: assetURL.path
        )
        let second = try CoreAIModelLoader.resourceFingerprint(for: directory)
        let metadataDate = try metadataURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate

        #expect(metadataDate == fixedMetadataDate)
        #expect(first != second)
    }

    @Test func resourceIdentityChangesWhenConfiguredAssetsChange() throws {
        let directory = try coreAITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assetURL = directory.appending(path: "weights.bin", directoryHint: .notDirectory)
        let initialBytes = Data([0, 1, 2, 3, 4, 5, 6, 7])
        let replacementBytes = Data([7, 6, 5, 4, 3, 2, 1, 0])
        try initialBytes.write(to: assetURL)
        let originalValues = try assetURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        let originalModificationDate = try #require(originalValues.contentModificationDate)
        let originalFileSize = try #require(originalValues.fileSize)
        let configuration = EvaluationCoreAIConfiguration(resourcesPath: directory.path)

        let first = try CoreAIModelLoader.resourceIdentity(for: configuration)
        #expect(initialBytes.count == replacementBytes.count)
        let handle = try FileHandle(forWritingTo: assetURL)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: replacementBytes)
        try handle.close()

        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        var statusChangeObserved = false
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if try CoreAIModelLoader.resourceIdentity(for: configuration) != first {
                statusChangeObserved = true
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        #expect(statusChangeObserved)
        guard statusChangeObserved else { return }

        try FileManager.default.setAttributes(
            [.modificationDate: originalModificationDate],
            ofItemAtPath: assetURL.path
        )
        let restoredValues = try assetURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        #expect(restoredValues.fileSize == originalFileSize)
        #expect(restoredValues.contentModificationDate == originalModificationDate)
        let second = try CoreAIModelLoader.resourceIdentity(for: configuration)

        #expect(first.resourceURL == directory.standardizedFileURL.resolvingSymlinksInPath())
        #expect(first != second)
    }

    @Test func cancelledCoreAIRunIsNotRecordedAsAModelLoadFailure() async {
        var suite = EvaluationSuite()
        suite.scoringMode = .review
        suite.modelConfiguration.provider = .coreAI

        let task = Task {
            withUnsafeCurrentTask { task in task?.cancel() }
            return await EvaluationRunner().run(
                id: UUID(),
                suiteRevision: "test",
                startedAt: Date(),
                suite: suite,
                images: []
            ) { _, _, _ in }
        }
        let run = await task.value

        #expect(run.cancelled)
        #expect(run.terminationReason == "cancelled")
        #expect(run.results.isEmpty)
    }

    @Test func failedCoreAIAdmissionDoesNotBorrowSystemModelCapabilities() async {
        var suite = EvaluationSuite()
        suite.scoringMode = .review
        suite.modelConfiguration.provider = .coreAI
        suite.modelConfiguration.coreAISettings.resourcesPath = "/missing-core-ai-\(UUID().uuidString)"

        let run = await EvaluationRunner().run(
            id: UUID(),
            suiteRevision: "missing-core-ai",
            startedAt: Date(),
            suite: suite,
            images: []
        ) { _, _, _ in }

        #expect(run.results.count == 1)
        #expect(run.results.first?.errorCategory == "modelAssetsUnavailable")
        #expect(run.environment.modelContextSize == 0)
        #expect(run.execution?.capabilities.isEmpty == true)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["FOUNDATION_EVALS_COREAI_TEST_RESOURCES"]?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
            "Set FOUNDATION_EVALS_COREAI_TEST_RESOURCES to a Core AI LanguageBundle folder."
        ),
        .timeLimit(.minutes(2))
    )
    func configuredResourcesLoadAndGenerate() async throws {
        let resourcesPath = try #require(
            ProcessInfo.processInfo.environment["FOUNDATION_EVALS_COREAI_TEST_RESOURCES"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let loader = CoreAIModelLoader()
        let loaded = try await loader.load(
            configuration: EvaluationCoreAIConfiguration(resourcesPath: resourcesPath)
        )

        #expect(!loaded.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(loaded.contextSize > 0)
        #expect((loaded.estimatedSizeOnDiskBytes ?? 0) > 0)

        let reportedCapabilities = loaded.capabilities
        let runtimeCapabilities = loaded.model.capabilities
        for capability: LanguageModelCapabilities.Capability in [
            .vision, .guidedGeneration, .reasoning, .toolCalling,
        ] {
            #expect(reportedCapabilities.contains(capability) == runtimeCapabilities.contains(capability))
        }

        let session = LanguageModelSession(model: loaded.model)
        let response = try await session.respond(
            to: Prompt { "Respond with one short token." },
            options: GenerationOptions(
                samplingMode: .greedy,
                maximumResponseTokens: 8,
                toolCallingMode: .disallowed
            )
        )

        #expect(response.usage.input.totalTokenCount > 0)
        #expect(response.usage.output.totalTokenCount <= 8)
        #expect(
            response.usage.output.reasoningTokenCount
                <= response.usage.output.totalTokenCount
        )

        let postGenerationCapabilities = loaded.model.capabilities
        for capability: LanguageModelCapabilities.Capability in [
            .vision, .guidedGeneration, .reasoning, .toolCalling,
        ] {
            #expect(
                postGenerationCapabilities.contains(capability)
                    == reportedCapabilities.contains(capability)
            )
        }
    }
}

private func coreAITemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
