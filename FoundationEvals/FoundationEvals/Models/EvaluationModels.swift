import Foundation

enum ScoringMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case review
    case exactMatch
    case containsExpected
    case modelJudge

    var id: Self { self }

    var title: String {
        switch self {
        case .review: "Review only"
        case .exactMatch: "Exact match"
        case .containsExpected: "Contains expected"
        case .modelJudge: "Model judge"
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
    var id = UUID()
    var name = "My Foundation Model Eval"
    var version = "v1"
    var instructions = "Answer accurately and concisely."
    var criteria = "The response is correct, relevant, and follows the instructions."
    var scoringMode = ScoringMode.modelJudge
    var repetitions = 1
    var cases = [
        EvaluationCase(
            name: "Example",
            prompt: "Explain why the sky appears blue in two sentences.",
            expected: ""
        )
    ]
    var attachments: [EvaluationAttachment] = []
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
