import Foundation

struct EvaluationJudgeTrace: Codable, Sendable {
    var instructions: String
    var prompt: String
    var rawResponse: String? = nil
    var checks: [EvaluationJudgeCriterionTrace]? = nil
    var validationError: String? = nil
    var attempts: [EvaluationJudgeAttemptTrace]? = nil
    var judgedCriterionIndexes: [Int]? = nil
    var refusal: EvaluationRefusalTrace? = nil
    /// Nil for legacy traces; never invent a historical request policy.
    var policyVersion: String? = nil
}

struct EvaluationJudgeAttemptTrace: Codable, Sendable {
    var prompt: String
    var rawResponse: String? = nil
    var validationError: String? = nil
    /// Exact request instructions, not reconstructed from the current policy.
    var instructions: String? = nil
    var policyVersion: String? = nil
}
