import Foundation

struct MetricScore: Equatable, Sendable {
    var status: EvaluationResultStatus
    var rationale: String?
}

enum MetricScorer {
    static func evaluate(mode: ScoringMode, expected: String, response: String) -> MetricScore {
        switch mode {
        case .review, .modelJudge:
            return MetricScore(status: .unscored, rationale: nil)
        case .exactMatch:
            let matches = response.trimmingCharacters(in: .whitespacesAndNewlines)
                == expected.trimmingCharacters(in: .whitespacesAndNewlines)
            return MetricScore(
                status: matches ? .passed : .failed,
                rationale: matches ? "Exact match after trimming whitespace." : "Response did not exactly match the expected text."
            )
        case .containsExpected:
            let matches = response.range(of: expected, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            return MetricScore(
                status: matches ? .passed : .failed,
                rationale: matches ? "Response contains the expected text." : "Response does not contain the expected text."
            )
        }
    }
}
