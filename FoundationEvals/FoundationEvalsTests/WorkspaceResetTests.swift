import Foundation
import Testing
@testable import FoundationEvals

@MainActor
struct WorkspaceResetTests {
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
        try store.clearRunHistory()
        #expect(store.runs.isEmpty)
        #expect(store.selection == .suite)
        let reloaded = EvaluationStore(supportDirectory: directory)
        #expect(reloaded.runs.isEmpty)
        #expect(reloaded.draftSuite == draft)
        #expect(reloaded.notice == nil)
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
