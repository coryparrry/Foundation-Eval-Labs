import Foundation
import Testing
@testable import FoundationEvals

@MainActor
struct PromptTextEditorTests {
    @Test func promptTypingDoesNotPublishTheWholeSuiteUntilFlushed() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let original = store.draftSuite
        let id = original.cases[0].id
        for index in 0..<50 { store.editPrompt("Prompt character \(index)", for: id) }
        #expect(store.draftSuite == original)
        #expect(store.promptText(for: id) == "Prompt character 49")
        let runtime = FoundationEvalsMCPRuntime(store: store)
        await runtime.prepareForTermination()
        #expect(store.draftSuite.cases[0].prompt == "Prompt character 49")
        #expect(EvaluationStore(supportDirectory: directory).draftSuite == store.draftSuite)
    }

    @Test func pendingPromptSurvivesStaleRemoteReplacementAndDuplicatesCorrectly() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let id = store.draftSuite.cases[0].id
        let revision = store.suiteRevision
        var replacement = store.suite
        replacement.name = "Remote replacement"
        store.editPrompt("Latest prompt", for: id)
        #expect(throws: (any Error).self) {
            try store.replaceSuite(replacement, expectedRevision: revision, confirmDeletes: true)
        }
        #expect(store.draftSuite.cases[0].prompt == "Latest prompt")
        store.editPrompt("Duplicate this pending text", for: id)
        store.duplicateCase(id: id)
        #expect(store.draftSuite.cases[1].prompt == "Duplicate this pending text")
        store.editPrompt("Discard this on reset", for: id)
        try store.resetSuite()
        _ = store.saveSuite()
        #expect(store.draftSuite.cases[0].prompt.isEmpty)
        #expect(store.promptText(for: id).isEmpty)
    }

}
