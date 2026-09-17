import Foundation
import AppKit
import Testing
@testable import FoundationEvals

@MainActor
struct WorkspaceResetTests {
    @Test func resetRemovesSuiteAttachmentBytesButPreservesRunEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        let imported = try await store.importAttachment(
            id: UUID(), name: "private.png", mediaType: "image/png", data: image,
            expectedRevision: store.suiteRevision
        )
        let root = suiteDirectory(store, in: directory)
        let storedFilename = try #require(imported.attachment.storedFilename)
        let attachmentURL = root.appending(path: "Attachments/\(storedFilename)")
        let runEvidenceURL = root.appending(path: "RunEvidence/fixture/private.png")
        try FileManager.default.createDirectory(
            at: runEvidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try image.write(to: runEvidenceURL)

        try store.resetSuite()

        #expect(store.suite.attachments.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: attachmentURL.path))
        #expect(FileManager.default.fileExists(atPath: runEvidenceURL.path))
        #expect(EvaluationStore(supportDirectory: directory).suite.attachments.isEmpty)
    }

    @Test func blankSuiteReplacesCanonicalAndIncompleteDraftAfterReload() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let originalID = store.suite.id
        store.draftSuite.name = "Old draft"
        store.draftSuite.cases[0].prompt = ""
        #expect(!store.saveSuite())
        try store.resetSuite()
        let reloaded = EvaluationStore(supportDirectory: directory)
        #expect(reloaded.suite == store.suite)
        #expect(reloaded.draftSuite == store.draftSuite)
        #expect(reloaded.suite.id == originalID)
        #expect(reloaded.selectedSuiteRecord.name == "Untitled Suite")
        #expect(reloaded.draftSuite.name == "Untitled Suite")
        #expect(reloaded.draftSuite.cases.count == 1)
        #expect(reloaded.draftSuite.cases[0].prompt.isEmpty)
        #expect(reloaded.draftSuite.instructions.isEmpty)
        #expect(reloaded.draftSuite.criteria.isEmpty)
        #expect(reloaded.runBlocker != nil)
        #expect(reloaded.notice == nil)
    }

    @Test func clearingHistoryRemovesTracesAndRecoveryMarkerButKeepsDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let run = EvaluationRun(
            id: UUID(),
            suiteID: store.suite.id,
            suiteName: store.suite.name,
            suiteVersion: store.suite.version,
            instructions: store.suite.instructions,
            criteria: store.suite.criteria,
            scoringMode: .review,
            repetitions: 1,
            judgePromptVersion: nil,
            judgePassingScore: nil,
            plannedSampleCount: 5,
            startedAt: .now,
            completedAt: .now,
            cancelled: true,
            terminationReason: "cancelled",
            environment: EvaluationEnvironment(
                operatingSystem: "Test",
                locale: "en_GB",
                model: "Test model",
                modelContextSize: 4096
            ),
            attachments: [],
            results: []
        )
        try CanonicalJSON.data(for: run).write(to: suiteDirectory(store, in: directory).appending(path: "Runs/\(run.id).json"))
        store.runs = [run]
        store.selection = .run(run.id)
        store.draftSuite.cases[0].prompt = ""
        _ = store.saveSuite()
        let draft = store.draftSuite
        try Data("unreadable".utf8).write(to: suiteDirectory(store, in: directory).appending(path: "Runs/broken.json"))
        try Data("obsolete".utf8).write(to: suiteDirectory(store, in: directory).appending(path: "active-run.json"))
        let evidence = suiteDirectory(store, in: directory).appending(path: "RunEvidence/\(run.id)")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try Data("private image fixture".utf8).write(to: evidence.appending(path: "image.png"))
        let pending = suiteDirectory(store, in: directory).appending(path: "RunDeletions")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        try Data("old tombstone".utf8).write(to: pending.appending(path: "previous.json"))
        try store.clearRunHistory()
        #expect(store.runs.isEmpty)
        #expect(store.selection == .suite)
        let reloaded = EvaluationStore(supportDirectory: directory)
        #expect(reloaded.runs.isEmpty)
        #expect(reloaded.draftSuite == draft)
        #expect(reloaded.notice == nil)
        #expect(!FileManager.default.fileExists(atPath: evidence.deletingLastPathComponent().path))
        #expect(!FileManager.default.fileExists(atPath: pending.path))
    }

    @Test func clearingHistoryCanRetryAfterCopiedEvidenceCleanupFails() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let root = suiteDirectory(store, in: directory)
        let evidence = root.appending(path: "RunEvidence")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try Data("private fixture".utf8).write(to: evidence.appending(path: "image.png"))
        try Data("unreadable run".utf8).write(to: root.appending(path: "Runs/broken.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: evidence.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: evidence.path) }
        #expect(throws: (any Error).self) { try store.clearRunHistory() }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Runs/broken.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "RunDeletions/broken.json").path))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: evidence.path)
        try EvaluationStore(supportDirectory: directory).clearRunHistory()
        #expect(!FileManager.default.fileExists(atPath: evidence.path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "RunDeletions").path))
    }

    @Test func resetRejectsRunningAndFileOperations() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let original = store.draftSuite
        store.isRunning = true
        #expect(!store.canResetWorkspace)
        #expect(throws: (any Error).self) { try store.resetSuite() }
        #expect(throws: (any Error).self) { try store.clearRunHistory() }
        store.isRunning = false
        store.isProcessingFiles = true
        #expect(throws: (any Error).self) { try store.resetSuite() }
        store.isProcessingFiles = false
        store.isImportingFiles = true
        #expect(throws: (any Error).self) { try store.clearRunHistory() }
        #expect(store.draftSuite == original)
    }

    @Test func failedResetWritePreservesCurrentSuite() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let original = store.draftSuite
        try FileManager.default.removeItem(at: suiteDirectory(store, in: directory).appending(path: "suite.json"))
        try FileManager.default.createDirectory(at: suiteDirectory(store, in: directory).appending(path: "suite.json"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try store.resetSuite() }
        #expect(store.draftSuite == original)
        #expect(store.suite == original)
    }

    @Test func unreadableCanonicalSnapshotAbortsSaveBeforeMutation() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let original = store.suite
        let suiteURL = suiteDirectory(store, in: directory).appending(path: "suite.json")
        try FileManager.default.removeItem(at: suiteURL)
        try FileManager.default.createDirectory(at: suiteURL, withIntermediateDirectories: true)

        store.draftSuite.name = "Must not be committed"
        #expect(!store.saveSuite())
        #expect(store.suite == original)
        #expect(FileManager.default.fileExists(atPath: suiteURL.path))
        #expect(try suiteURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    }

    @Test func resetCatalogSnapshotFailurePreservesCanonicalRepositoryAndAttachmentBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = directory.appending(path: "repo")
        try FileManager.default.createDirectory(at: repository.appending(path: ".git"), withIntermediateDirectories: true)
        let storage = directory.appending(path: "storage")
        let store = EvaluationStore(supportDirectory: storage)
        try store.linkSelectedProject(toRepository: repository.path)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        let imported = try await store.importAttachment(
            id: UUID(), name: "keep.png", mediaType: "image/png", data: image,
            expectedRevision: store.suiteRevision
        )
        let suiteURL = suiteDirectory(store, in: storage).appending(path: "suite.json")
        let originalSuiteData = try Data(contentsOf: suiteURL)
        let definitionURL = try #require(EvaluationWorkspacePersistence.repositoryDefinitionURL(
            project: store.selectedProject, suite: store.selectedSuiteRecord
        ))
        let originalDefinitionData = try Data(contentsOf: definitionURL)
        let storedFilename = try #require(imported.attachment.storedFilename)
        let attachmentURL = suiteDirectory(store, in: storage)
            .appending(path: "Attachments/\(storedFilename)")
        let originalAttachmentData = try Data(contentsOf: attachmentURL)
        let originalSuite = store.suite
        let originalDraft = store.draftSuite
        let originalWorkspace = store.workspace

        let catalogURL = storage.appending(path: EvaluationWorkspacePersistence.catalogFilename)
        try FileManager.default.removeItem(at: catalogURL)
        try FileManager.default.createDirectory(at: catalogURL, withIntermediateDirectories: true)

        #expect(throws: (any Error).self) { try store.resetSuite() }
        #expect(store.suite == originalSuite)
        #expect(store.draftSuite == originalDraft)
        #expect(store.workspace == originalWorkspace)
        #expect(try Data(contentsOf: suiteURL) == originalSuiteData)
        #expect(try Data(contentsOf: definitionURL) == originalDefinitionData)
        #expect(try Data(contentsOf: attachmentURL) == originalAttachmentData)
    }

    @Test func resetDoesNotFollowSymlinkedAttachmentsDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let root = suiteDirectory(store, in: directory)
        let target = directory.appending(path: "outside-attachments", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let targetFile = target.appending(path: "must-survive.txt")
        let bytes = Data("outside private storage".utf8)
        try bytes.write(to: targetFile)
        let attachments = root.appending(path: "Attachments", directoryHint: .isDirectory)
        try FileManager.default.removeItem(at: attachments)
        try FileManager.default.createSymbolicLink(at: attachments, withDestinationURL: target)

        try store.resetSuite()

        #expect(store.notice?.contains("private attachment") == true)
        #expect(FileManager.default.fileExists(atPath: targetFile.path))
        #expect(try Data(contentsOf: targetFile) == bytes)
    }

    @Test func resettingLinkedSuiteUpdatesItsDefinitionAndPreservesOtherSuites() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = directory.appending(path: "repo")
        try FileManager.default.createDirectory(at: repository.appending(path: ".git"), withIntermediateDirectories: true)
        let storage = directory.appending(path: "storage")
        let store = EvaluationStore(supportDirectory: storage)
        let untouchedID = store.selectedSuiteID
        let untouchedSuite = store.suite
        let resetID = try store.createSuite(name: "Reset this suite")
        try store.linkSelectedProject(toRepository: repository.path)
        let definitionURL = try #require(EvaluationWorkspacePersistence.repositoryDefinitionURL(
            project: store.selectedProject, suite: store.selectedSuiteRecord
        ))
        try store.resetSuite()
        let definition = try CanonicalJSON.decode(EvaluationSuiteDefinition.self, from: Data(contentsOf: definitionURL))
        #expect(definition == EvaluationSuiteDefinition(suite: store.suite))
        let reloaded = EvaluationStore(supportDirectory: storage)
        #expect(reloaded.selectedSuiteID == resetID)
        #expect(reloaded.draftSuite == store.draftSuite)
        try reloaded.switchSuite(id: untouchedID)
        #expect(reloaded.suite == untouchedSuite)
    }

    @Test func resettingLinkedSuitePreservesAnExternalDefinitionConflict() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = directory.appending(path: "repo")
        try FileManager.default.createDirectory(at: repository.appending(path: ".git"), withIntermediateDirectories: true)
        let store = EvaluationStore(supportDirectory: directory.appending(path: "storage"))
        try store.linkSelectedProject(toRepository: repository.path)
        let original = store.suite
        let definitionURL = try #require(EvaluationWorkspacePersistence.repositoryDefinitionURL(
            project: store.selectedProject, suite: store.selectedSuiteRecord
        ))
        var external = EvaluationSuiteDefinition(suite: original)
        external.instructions = "Edited in the repository"
        try CanonicalJSON.data(for: external).write(to: definitionURL)
        #expect(throws: (any Error).self) { try store.resetSuite() }
        #expect(store.suite == original)
        #expect(try CanonicalJSON.decode(EvaluationSuiteDefinition.self, from: Data(contentsOf: definitionURL)) == external)
    }

    private func suiteDirectory(_ store: EvaluationStore, in directory: URL) -> URL {
        EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory, projectID: store.selectedProjectID, suiteID: store.selectedSuiteID
        )
    }
}
