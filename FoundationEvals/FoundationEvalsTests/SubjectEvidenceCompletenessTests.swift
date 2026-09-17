import Foundation
import Testing
@testable import FoundationEvals

struct SubjectEvidenceCompletenessTests {
    @Test func generationErrorMessageMakesPartialResponseIncompleteWithoutCategory() {
        let result = sample(response: "Partial response", errorMessage: "Generation stopped")

        #expect(!result.hasCompleteSubjectEvidenceForJudging)
    }

    @Test func normalCompleteResponseIsComplete() {
        let result = sample(response: "Complete response")

        #expect(result.hasCompleteSubjectEvidenceForJudging)
    }

    @Test func judgeOnlyErrorDoesNotInvalidateCompleteSubjectEvidence() {
        let result = sample(
            response: "Complete response",
            judgeErrorCategory: "judgeUnavailable",
            judgeErrorMessage: "The judge could not be reached"
        )

        #expect(result.hasCompleteSubjectEvidenceForJudging)
    }

    private func sample(
        response: String,
        errorCategory: String? = nil,
        errorMessage: String? = nil,
        judgeErrorCategory: String? = nil,
        judgeErrorMessage: String? = nil
    ) -> EvaluationSampleResult {
        EvaluationSampleResult(
            caseID: UUID(),
            caseName: "Subject evidence",
            repetition: 1,
            prompt: "Prompt",
            expected: "Expected",
            response: response,
            status: .passed,
            score: nil,
            rationale: nil,
            durationMilliseconds: 1,
            usage: EvaluationUsage(),
            errorCategory: errorCategory,
            errorMessage: errorMessage,
            judgeErrorCategory: judgeErrorCategory,
            judgeErrorMessage: judgeErrorMessage
        )
    }
}
