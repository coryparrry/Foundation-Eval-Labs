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
            "Use a separate call to the selected model provider with fixed judge settings. The judge scores 1–4; 3 or 4 passes."
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
        case .modelJudge: "Give the judge a known-good answer when correctness can be verified. An exact match passes deterministically without asking the model judge."
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

struct EvaluationAttachmentImportResult: Codable, Sendable {
    var attachment: EvaluationAttachment
    var truncated: Bool
    var duplicate: Bool
    var revision: String
}

enum EvaluationModelProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case onDevice
    case privateCloudCompute

    var id: Self { self }

    var title: String {
        switch self {
        case .onDevice: "On device"
        case .privateCloudCompute: "Private Cloud Compute"
        }
    }

    var detail: String {
        switch self {
        case .onDevice:
            "Keeps prompts on this Mac. The current system model supports tools but not explicit reasoning levels."
        case .privateCloudCompute:
            "Supports explicit reasoning and a larger context. Requires a network connection, available quota, and Apple's managed entitlement."
        }
    }
}

enum EvaluationReasoningLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case light
    case moderate
    case deep

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .moderate: "Moderate"
        case .deep: "Deep"
        }
    }
}

enum EvaluationSamplingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case greedy
    case topK
    case probability

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .greedy: "Greedy"
        case .topK: "Random · top K"
        case .probability: "Random · probability"
        }
    }
}

enum EvaluationReferenceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case inline
    case lookupTool

    var id: Self { self }

    var title: String {
        switch self {
        case .inline: "Include in prompt"
        case .lookupTool: "Search with tool"
        }
    }
}

enum EvaluationContextPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case fitReferences
    case requireFullInput

    var id: Self { self }

    var title: String {
        switch self {
        case .fitReferences: "Fit reference text"
        case .requireFullInput: "Require full input"
        }
    }
}

struct EvaluationModelConfiguration: Codable, Equatable, Sendable {
    static let currentBehaviorVersion = "foundation-evals-v6"

    var provider: EvaluationModelProvider = .onDevice
    var reasoningLevel: EvaluationReasoningLevel = .automatic
    var samplingMode: EvaluationSamplingMode = .automatic
    var temperatureEnabled = false
    var temperature = 0.7
    var seedEnabled = false
    var seed: UInt64 = 42
    var topK = 40
    var probabilityThreshold = 0.9
    var maximumResponseTokens = 1_024
    var maximumInputTokens: Int? = nil
    var referenceMode: EvaluationReferenceMode = .inline
    var contextPolicy: EvaluationContextPolicy = .fitReferences
    var maximumToolCalls = 2
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
    var modelConfiguration = EvaluationModelConfiguration()
    var features = EvaluationFeatureConfiguration()
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

    init() {}

    private enum CodingKeys: String, CodingKey {
        case id, name, version, instructions, criteria, scoringMode, repetitions, modelConfiguration, features, cases, attachments
    }

    init(from decoder: Decoder) throws {
        let defaults = EvaluationSuite()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? defaults.id
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? defaults.name
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? defaults.version
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? defaults.instructions
        criteria = try container.decodeIfPresent(String.self, forKey: .criteria) ?? defaults.criteria
        scoringMode = try container.decodeIfPresent(ScoringMode.self, forKey: .scoringMode) ?? defaults.scoringMode
        repetitions = try container.decodeIfPresent(Int.self, forKey: .repetitions) ?? defaults.repetitions
        modelConfiguration = try container.decodeIfPresent(EvaluationModelConfiguration.self, forKey: .modelConfiguration)
            ?? defaults.modelConfiguration
        features = try container.decodeIfPresent(EvaluationFeatureConfiguration.self, forKey: .features) ?? defaults.features
        cases = try container.decodeIfPresent([EvaluationCase].self, forKey: .cases) ?? defaults.cases
        attachments = try container.decodeIfPresent([EvaluationAttachment].self, forKey: .attachments) ?? defaults.attachments
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

struct EvaluationSampleTiming: Codable, Sendable {
    var preparationMilliseconds: Double?
    var generationMilliseconds: Double?
    var scoringMilliseconds: Double?
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
    var reasoningText: String? = nil
    var status: EvaluationResultStatus
    var score: Int?
    var rationale: String?
    var durationMilliseconds: Double
    var usage: EvaluationUsage
    var judgeDurationMilliseconds: Double?
    var judgeUsage: EvaluationUsage?
    var judgeReasoningText: String? = nil
    var errorCategory: String?
    var errorMessage: String?
    var judgeErrorCategory: String?
    var judgeErrorMessage: String?
    var toolCalls: [EvaluationToolCallTrace]? = nil
    var timing: EvaluationSampleTiming? = nil
    var featureTrace: EvaluationFeatureTrace? = nil
}

struct EvaluationToolCallTrace: Codable, Sendable {
    var toolName: String
    var callIndex: Int
    var matchedFiles: [String]
    var outputCharacterCount: Int
    var outcome: String
    var durationMilliseconds: Double? = nil
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

struct EvaluationExecutionTrace: Codable, Sendable {
    var behaviorVersion: String
    var configuration: EvaluationModelConfiguration
    var modelDisplayName: String
    var capabilities: [String]
    var toolNames: [String]
    var effectiveInputTokenLimit: Int? = nil
    var reservedToolOutputTokens: Int? = nil
    var reservedJudgeOverheadTokens: Int? = nil
    var inputTokenCountingMethod: String? = nil
    var features: EvaluationFeatureConfiguration? = nil
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
    var plannedSampleCount: Int?
    var suiteRevision: String? = nil
    var plannedCases: [EvaluationCase]? = nil
    var startedAt: Date
    var completedAt: Date
    var cancelled: Bool
    var terminationReason: String?
    var environment: EvaluationEnvironment
    var attachments: [EvaluationAttachmentTrace]
    var results: [EvaluationSampleResult]
    var execution: EvaluationExecutionTrace? = nil

    var passedCount: Int { results.count(where: { $0.status == .passed }) }
    var failedCount: Int { results.count(where: { $0.status == .failed }) }
    var errorCount: Int {
        results.count(where: { $0.errorCategory != nil || $0.judgeErrorCategory != nil })
    }
    var scoredCount: Int { passedCount + failedCount }
    var plannedResultCount: Int { plannedSampleCount ?? results.count }
    var stoppedEarly: Bool {
        !cancelled && terminationReason != nil && results.count < plannedResultCount
    }

    var terminationSummary: String? {
        switch terminationReason {
        case "rateLimited": "Rate limited"
        case "quotaLimitReached": "Cloud quota reached"
        case "networkFailure": "Network failure"
        case "serviceUnavailable": "Service unavailable"
        case "modelUnavailable": "Model unavailable"
        case "modelAssetsUnavailable": "Model assets unavailable"
        case "interrupted": "Interrupted by app exit"
        case .some(let reason): reason
        case nil: nil
        }
    }

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

    var totalDuration: Duration {
        .seconds(completedAt.timeIntervalSince(startedAt))
    }

    var totalTokens: Int {
        results.reduce(0) { $0 + $1.usage.totalTokens + ($1.judgeUsage?.totalTokens ?? 0) }
    }
}

enum EvaluationRunPhase: String, Codable, Sendable {
    case running
    case cancellationRequested
    case completed
    case cancelled
    case interrupted
    case stopped
}

struct EvaluationActiveRun: Codable, Equatable, Sendable {
    var id: UUID
    var suiteRevision: String
    var startedAt: Date
    var completedSamples: Int
    var totalSamples: Int
    var cancellationRequested: Bool
}

struct EvaluationRunOperation: Codable, Sendable {
    var id: UUID
    var suiteRevision: String?
    var phase: EvaluationRunPhase
    var completedSamples: Int
    var totalSamples: Int
    var startedAt: Date
    var completedAt: Date?
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
