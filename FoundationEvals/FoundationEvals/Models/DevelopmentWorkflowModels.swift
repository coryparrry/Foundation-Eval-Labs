import CryptoKit
import Foundation

// MARK: - Workspace catalog

struct EvaluationWorkspaceCatalog: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion = currentFormatVersion
    var selectedProjectID: UUID
    var projects: [EvaluationProject]
    var migratedLegacyStorageAt: Date?
}

struct EvaluationProject: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var repository: EvaluationRepositoryLink?
    var selectedSuiteID: UUID
    var suites: [EvaluationSuiteRecord]

    var isArchived: Bool { archivedAt != nil }
}

struct EvaluationSuiteRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var repositoryDefinitionPath: String?
    var lastRepositoryRevision: String?

    var isArchived: Bool { archivedAt != nil }
}

struct EvaluationRepositoryLink: Codable, Equatable, Sendable {
    var rootPath: String
    var definitionsDirectory = ".foundation-evals/suites"
}

/// Git-reviewed suite content. Attachments, secrets, responses, traces, approvals,
/// and machine paths deliberately remain in local state.
struct EvaluationSuiteDefinition: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion = currentFormatVersion
    var id: UUID
    var name: String
    var version: String
    var instructions: String
    var criteria: String
    var scoringMode: ScoringMode
    var repetitions: Int
    var modelConfiguration: EvaluationModelConfiguration
    var features: EvaluationFeatureConfiguration
    var cases: [EvaluationCase]
    var judgeConfiguration: EvaluationJudgeConfiguration
    var releasePolicy: EvaluationReleasePolicy

    init(suite: EvaluationSuite) {
        id = suite.id
        name = suite.name
        version = suite.version
        instructions = suite.instructions
        criteria = suite.criteria
        scoringMode = suite.scoringMode
        repetitions = suite.repetitions
        modelConfiguration = suite.modelConfiguration
        features = suite.features
        cases = suite.cases
        var definitionJudge = suite.judgeConfiguration
        definitionJudge.connectionID = nil
        definitionJudge.externalEvidenceApprovedAt = nil
        definitionJudge.approvedConnectionID = nil
        definitionJudge.approvedIncludeReferenceAttachments = nil
        definitionJudge.approvedConnectionDigest = nil
        judgeConfiguration = definitionJudge
        releasePolicy = suite.releasePolicy
    }

    func applyingLocalState(from suite: EvaluationSuite) -> EvaluationSuite {
        var result = suite
        result.id = id
        result.name = name
        result.version = version
        result.instructions = instructions
        result.criteria = criteria
        result.scoringMode = scoringMode
        result.repetitions = repetitions
        result.modelConfiguration = modelConfiguration
        result.features = features
        result.cases = cases
        var appliedJudge = judgeConfiguration
        appliedJudge.connectionID = suite.judgeConfiguration.connectionID
        appliedJudge.externalEvidenceApprovedAt = suite.judgeConfiguration.externalEvidenceApprovedAt
        appliedJudge.approvedConnectionID = suite.judgeConfiguration.approvedConnectionID
        appliedJudge.approvedIncludeReferenceAttachments = suite.judgeConfiguration.approvedIncludeReferenceAttachments
        appliedJudge.approvedConnectionDigest = suite.judgeConfiguration.approvedConnectionDigest
        result.judgeConfiguration = appliedJudge
        result.releasePolicy = releasePolicy
        return result
    }
}

struct EvaluationProjectOverview: Identifiable, Sendable {
    var id: UUID
    var name: String
    var suiteCount: Int
    var suitesNeedingChecks: Int
    var latestRunAt: Date?
    var hasStaleResults: Bool
}

// MARK: - Judge connections and provenance

enum EvaluationJudgeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case sameModel
    case connection

    var id: Self { self }
}

struct EvaluationJudgeConfiguration: Codable, Equatable, Sendable {
    var mode: EvaluationJudgeMode = .sameModel
    var connectionID: UUID?
    var externalEvidenceApprovedAt: Date?
    var includeReferenceAttachments = true
    var approvedConnectionID: UUID?
    var approvedIncludeReferenceAttachments: Bool?
    var approvedConnectionDigest: String?

    var usesExternalConnection: Bool { mode == .connection }
    func hasCurrentExternalEvidenceApproval(for connection: EvaluationJudgeConnection) -> Bool {
        externalEvidenceApprovedAt != nil
            && approvedConnectionID == connectionID
            && approvedIncludeReferenceAttachments == includeReferenceAttachments
            && approvedConnectionDigest == connection.disclosureDigest
    }
}

enum EvaluationJudgeConnectionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case localCompatible
    case openRouter
    case customCompatible

    var id: Self { self }

    var title: String {
        switch self {
        case .localCompatible: "Local compatible endpoint"
        case .openRouter: "OpenRouter"
        case .customCompatible: "Custom compatible endpoint"
        }
    }
}

struct EvaluationJudgeCapabilities: Codable, Equatable, Sendable {
    var structuredOutputs = true
    var multimodal = false
}

struct EvaluationJudgeConnection: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var kind: EvaluationJudgeConnectionKind
    var baseURL: String
    var modelID: String
    var capabilities = EvaluationJudgeCapabilities()
    var requestTimeoutSeconds = 60.0
    var providerOrder: [String] = []
    var inputUSDPerMillionTokens: Double?
    var outputUSDPerMillionTokens: Double?
    var lastCheckedAt: Date?
    var lastCheckMessage: String?

    var requiresAPIKey: Bool { kind != .localCompatible }

    var disclosureDigest: String {
        let fields = [
            kind.rawValue,
            baseURL,
            modelID,
            providerOrder.joined(separator: "\u{1f}"),
            capabilities.structuredOutputs ? "structured" : "unstructured",
            capabilities.multimodal ? "multimodal" : "text"
        ]
        let framed = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return SHA256.hash(data: Data(framed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var validationIssue: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Name the judge connection." }
        guard !trimmedModel.isEmpty else { return "Enter the exact judge model ID." }
        guard let url = URL(string: baseURL), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else {
            return "Enter an absolute HTTP or HTTPS base URL."
        }
        if kind == .openRouter, scheme != "https" {
            return "OpenRouter connections must use HTTPS."
        }
        guard (1...300).contains(requestTimeoutSeconds) else {
            return "Judge timeout must be between 1 and 300 seconds."
        }
        if kind == .openRouter, providerOrder.isEmpty {
            return "Choose at least one explicit OpenRouter provider so judge routing cannot silently fall back."
        }
        guard Set(providerOrder).count == providerOrder.count,
              providerOrder.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return "Provider routing entries must be non-empty and unique."
        }
        return nil
    }
}

struct EvaluationJudgeIdentity: Codable, Equatable, Sendable {
    var mode: EvaluationJudgeMode
    var connectionID: UUID?
    var connectionName: String
    var endpointKind: EvaluationJudgeConnectionKind?
    var baseURL: String?
    var requestedModelID: String
    var reportedModelID: String?
    var provider: String?
    var providerOrder: [String]

    var displayName: String {
        let actual = reportedModelID ?? requestedModelID
        return "\(connectionName) · \(actual)"
    }
}

enum EvaluationCostAvailability: String, Codable, Sendable {
    case known
    case estimated
    case unavailable
}

struct EvaluationCost: Codable, Sendable {
    var availability: EvaluationCostAvailability
    var usd: Double?
    var explanation: String
}

enum EvaluationAssessmentOrigin: String, Codable, Sendable {
    case initialRun
    case reassessment
    case judgeCheck
}

struct EvaluationSampleAssessment: Identifiable, Codable, Sendable {
    var id: UUID
    var sampleID: UUID
    var status: EvaluationResultStatus
    var score: Int?
    var rationale: String?
    var trace: EvaluationJudgeTrace?
    var errorCategory: String?
    var errorMessage: String?
    var usage: EvaluationUsage?
    var durationMilliseconds: Double?
}

struct EvaluationAssessment: Identifiable, Codable, Sendable {
    var id: UUID
    var runID: UUID
    var createdAt: Date
    var origin: EvaluationAssessmentOrigin
    var judge: EvaluationJudgeIdentity
    var promptVersion: String
    var rubric: String
    var passingScore: Int
    var samples: [EvaluationSampleAssessment]
    var totalUsage: EvaluationUsage?
    var durationMilliseconds: Double
    var cost: EvaluationCost
    var supersedesAssessmentID: UUID?
    var observedJudgeIdentities: [EvaluationJudgeIdentity]? = nil

    var errorCount: Int { samples.count { $0.errorCategory != nil || $0.errorMessage != nil } }
}

struct EvaluationHumanCorrection: Identifiable, Codable, Sendable {
    var id: UUID
    var runID: UUID
    var assessmentID: UUID
    var sampleID: UUID
    var originalStatus: EvaluationResultStatus
    var originalScore: Int?
    var correctedStatus: EvaluationResultStatus
    var correctedScore: Int?
    var reason: String
    var reviewer: String?
    var createdAt: Date
}

struct EvaluationReviewedJudgeExample: Identifiable, Codable, Sendable {
    var id: UUID
    var sourceRunID: UUID
    var sourceAssessmentID: UUID
    var sampleID: UUID
    var expectedStatus: EvaluationResultStatus
    var reason: String
    var createdAt: Date
}

struct EvaluationBaselineApproval: Identifiable, Codable, Sendable {
    var id: UUID
    var runID: UUID
    var assessmentID: UUID?
    var suiteRevision: String
    var approvedAt: Date
    var note: String?
    var revokedAt: Date?

    var isCurrent: Bool { revokedAt == nil }
}

struct EvaluationSuiteLocalState: Codable, Sendable {
    var baselineApprovals: [EvaluationBaselineApproval] = []
    var humanCorrections: [EvaluationHumanCorrection] = []
    var reviewedJudgeExamples: [EvaluationReviewedJudgeExample] = []
    var experiments: [EvaluationExperiment] = []
}

// MARK: - Repository and experiment evidence

struct EvaluationRepositorySnapshot: Codable, Sendable {
    var rootPath: String
    var commit: String?
    var isDirty: Bool?
    var capturedAt: Date
    var error: String?

    var identitySummary: String {
        guard let commit else { return error ?? "Repository identity unavailable" }
        if isDirty == true { return "\(commit) with uncommitted changes" }
        if isDirty == false { return commit }
        return "\(commit); working-tree state unavailable"
    }
}

enum EvaluationExperimentDecision: String, Codable, CaseIterable, Sendable {
    case keepCurrent
    case adoptCandidate
    case collectMoreEvidence
    case inconclusive
}

struct EvaluationExperimentVariant: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var instructions: String
}

struct EvaluationExperiment: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var suiteRevision: String
    var casesDigest: String
    var scoringDigest: String
    var judgeDigest: String
    var current: EvaluationExperimentVariant
    var candidate: EvaluationExperimentVariant
    var executionOrder: [UUID]
    var runIDs: [UUID]
    var decision: EvaluationExperimentDecision?
}

struct EvaluationExperimentSummary: Sendable {
    var improvedCaseIDs: [UUID]
    var regressedCaseIDs: [UUID]
    var unchangedCaseIDs: [UUID]
    var currentMedianLatencyMilliseconds: Double?
    var candidateMedianLatencyMilliseconds: Double?
    var distinctCaseCoverage: Int
    var repetitionsPerCase: Int
    var confidenceInterval: ClosedRange<Double>?
    var suggestedDecision: EvaluationExperimentDecision
    var explanation: String
}

// MARK: - Release checks

struct EvaluationReleasePolicy: Codable, Equatable, Sendable {
    var required = false
    var criticalCaseIDs: [UUID] = []
    var maximumErrorCount = 0
    var maximumAverageLatencyMilliseconds: Double?
    var requireApprovedBaseline = false
    var maximumPassRateRegression = 0.0
}

enum EvaluationReleaseCheckExit: Int32, Codable, Sendable {
    case passed = 0
    case regression = 10
    case incompleteOrIncompatibleEvidence = 20
    case executionError = 30
}

struct EvaluationReleaseCheckReport: Codable, Sendable {
    var formatVersion = 1
    var projectID: UUID
    var suiteID: UUID
    var runID: UUID?
    var assessmentID: UUID?
    var outcome: EvaluationReleaseCheckExit
    var summary: String
    var failures: [String]
    var generatedAt: Date
}
