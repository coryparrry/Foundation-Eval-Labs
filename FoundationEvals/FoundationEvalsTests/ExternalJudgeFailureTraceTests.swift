import Foundation
import Testing
@testable import FoundationEvals

struct ExternalJudgeFailureTraceTests {
    @Test func exhaustedCompatibleJudgeAttemptsBecomePersistentTraceEvidence() throws {
        let attempts = [
            EvaluationJudgeAttemptTrace(
                prompt: "Initial verdict request",
                rawResponse: #"{"requirements":[]}"#,
                validationError: "Missing requirement 1"
            ),
            EvaluationJudgeAttemptTrace(
                prompt: "Repaired verdict request",
                rawResponse: "not-json",
                validationError: "Invalid JSON"
            ),
        ]
        let error = EvaluationCompatibleJudgeError.exhausted(
            message: "Invalid JSON",
            attempts: attempts
        )

        let trace = try #require(EvaluationRunner.externalJudgeFailureTrace(
            error,
            completedChecks: [],
            judgedCriterionIndexes: [1]
        ))

        #expect(trace.attempts?.count == 2)
        #expect(trace.prompt == "Repaired verdict request")
        #expect(trace.rawResponse == "not-json")
        #expect(trace.validationError == "Invalid JSON")
        #expect(trace.judgedCriterionIndexes == [1])
    }

    @Test func transportFailuresDoNotInventAttemptTraceEvidence() {
        let error = EvaluationCompatibleJudgeError.http(status: 503, detail: "Unavailable")
        #expect(EvaluationRunner.externalJudgeFailureTrace(
            error,
            completedChecks: [],
            judgedCriterionIndexes: [1]
        ) == nil)
    }
}
