import Foundation
import Testing
@testable import FoundationEvals

@MainActor
struct DeveloperRunPresentationTests {
    @Test func transportFailuresUseReadableSavedEvidence() {
        let status = failure(.disconnected, detail: "developerRunner:disconnected")
        #expect(DeveloperRunPresentation.failureMessage(for: status, sampleMessage: "Runner discovery was lost.")
            == "Runner discovery was lost.")
    }

    @Test func terminalKeysAreNeverShownWhenSavedEvidenceIsMissing() {
        for (phase, key) in [(DeveloperRunPhase.disconnected, "developerRunner:disconnected"),
                             (.timedOut, "developerRunner:deadlineExceeded"),
                             (.failed, "developerRunner:executionFailed")] {
            let message = DeveloperRunPresentation.failureMessage(for: failure(phase, detail: key), sampleMessage: key)
            #expect(!message.contains("developerRunner:"))
            #expect(!message.isEmpty)
        }
    }

    @Test func unsavedFailureKeepsItsSpecificExplanation() {
        let status = failure(.failed, detail: "The requested feature is no longer registered.")
        #expect(DeveloperRunPresentation.failureMessage(for: status, sampleMessage: nil) == status.detail)
    }

    private func failure(_ phase: DeveloperRunPhase, detail: String) -> DeveloperRunStatus {
        .init(id: UUID(), runnerID: UUID(), featureID: "verification.echo", phase: phase, detail: detail)
    }
}
