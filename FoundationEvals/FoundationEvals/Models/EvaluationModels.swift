import Foundation

enum ScoringMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case review
    case exactMatch
    case containsExpected
    case modelJudge

    var id: Self { self }

    var title: String {
        switch self {
        case .review: "Collect only"
        case .exactMatch: "Exact text"
        case .containsExpected: "Contains text"
        case .modelJudge: "AI rubric"
        }
    }

    var explanation: String {
        switch self {
        case .review:
            "Collect responses for external review. The app records traces but does not assign pass or fail."
        case .exactMatch:
            "Pass only when the complete response equals the expected response after trimming outer whitespace."
        case .containsExpected:
            "Pass when the response contains the required literal text, ignoring case and accents."
        case .modelJudge:
            "Use a second on-device model call for subjective quality. The judge scores 1–4; 3 or 4 passes."
        }
    }

    var expectedLabel: String {
        switch self {
        case .exactMatch: "Expected response (required)"
        case .containsExpected: "Required text (required)"
        case .modelJudge: "Reference answer (recommended for factual tasks)"
        case .review: ""
        }
    }

    var expectedHelp: String {
        switch self {
        case .exactMatch: "Example: Paris — the generated response must be exactly this text."
        case .containsExpected: "Example: Paris — this is literal text, not a regular expression."
        case .modelJudge: "Give the judge a known-good answer when correctness can be verified. Leave blank only for open-ended tasks."
        case .review: ""
        }
    }

    var needsExpected: Bool {
        self == .exactMatch || self == .containsExpected
    }
}

struct EvaluationCase: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var prompt: String
    var expected: String
}

enum EvaluationAttachmentKind: String, Codable, Sendable {
    case text
    case image
}

struct EvaluationAttachment: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var kind: EvaluationAttachmentKind
    var text: String?
    var storedFilename: String?
    var byteCount: Int
    var sha256: String
}

struct EvaluationSuite: Codable, Equatable, Sendable {
    static let legacyDefaultCriteria = "The response is correct, relevant, and follows the instructions."
    static let judgePassingScore = 3
    static let defaultRubric = """
        The response is factually correct or consistent with the supplied reference answer.
        The response directly answers the prompt without irrelevant material.
        The response follows every requested format, tone, and length constraint.
        """

    var id = UUID()
    var name = "My Foundation Model Eval"
    var version = "v1"
    var instructions = "Answer accurately and concisely."
    var criteria = EvaluationSuite.defaultRubric
    var scoringMode = ScoringMode.modelJudge
    var repetitions = 1
    var cases = [
        EvaluationCase(
            name: "Example",
            prompt: "Explain why the sky appears blue in two sentences.",
            expected: "Sunlight contains many wavelengths, and air molecules scatter shorter blue wavelengths more strongly than longer red ones. This Rayleigh scattering sends more blue light toward our eyes across the sky."
        )
    ]
    var attachments: [EvaluationAttachment] = []

    var rubricCriteria: [String] {
        criteria
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum EvaluationResultStatus: String, Codable, Sendable {
    case passed
    case failed
    case unscored
    case error
}

struct EvaluationUsage: Codable, Sendable {
    var inputTokens = 0
    var cachedInputTokens = 0
    var outputTokens = 0
    var reasoningTokens = 0

    var totalTokens: Int { inputTokens + outputTokens }

    mutating func add(_ other: Self) {
        inputTokens += other.inputTokens
        cachedInputTokens += other.cachedInputTokens
        outputTokens += other.outputTokens
        reasoningTokens += other.reasoningTokens
    }
}

struct EvaluationSampleResult: Identifiable, Codable, Sendable {
    var id = UUID()
    var caseID: UUID
    var caseName: String
    var repetition: Int
    var prompt: String
    var effectivePrompt: String?
    var expected: String
    var response: String
    var status: EvaluationResultStatus
    var score: Int?
    var rationale: String?
    var durationMilliseconds: Double
    var usage: EvaluationUsage
    var judgeDurationMilliseconds: Double?
    var judgeUsage: EvaluationUsage?
    var errorCategory: String?
    var errorMessage: String?
    var judgeErrorCategory: String?
    var judgeErrorMessage: String?
}

struct EvaluationAttachmentTrace: Codable, Sendable {
    var name: String
    var kind: EvaluationAttachmentKind
    var byteCount: Int
    var sha256: String
}

struct EvaluationEnvironment: Codable, Sendable {
    var operatingSystem: String
    var locale: String
    var model: String
    var modelContextSize: Int
}

struct EvaluationRun: Identifiable, Codable, Sendable {
    var id: UUID
    var suiteID: UUID
    var suiteName: String
    var suiteVersion: String
    var instructions: String
    var criteria: String
    var scoringMode: ScoringMode
    var repetitions: Int
    var judgePromptVersion: String?
    var judgePassingScore: Int?
    var startedAt: Date
    var completedAt: Date
    var cancelled: Bool
    var terminationReason: String?
    var environment: EvaluationEnvironment
    var attachments: [EvaluationAttachmentTrace]
    var results: [EvaluationSampleResult]

    var passedCount: Int { results.count(where: { $0.status == .passed }) }
    var failedCount: Int { results.count(where: { $0.status == .failed }) }
    var errorCount: Int {
        results.count(where: { $0.errorCategory != nil || $0.judgeErrorCategory != nil })
    }
    var scoredCount: Int { passedCount + failedCount }

    var passRate: Double? {
        scoredCount == 0 ? nil : Double(passedCount) / Double(scoredCount)
    }

    var averageScore: Double? {
        let scores = results.compactMap(\.score)
        return scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count)
    }

    var averageDurationMilliseconds: Double {
        results.isEmpty ? 0 : results.map(\.durationMilliseconds).reduce(0, +) / Double(results.count)
    }

    var totalTokens: Int {
        results.reduce(0) { $0 + $1.usage.totalTokens + ($1.judgeUsage?.totalTokens ?? 0) }
    }
}

enum SidebarSelection: Hashable {
    case suite
    case run(UUID)
}

struct ModelStatus: Sendable {
    var isAvailable: Bool
    var label: String
    var detail: String
}
