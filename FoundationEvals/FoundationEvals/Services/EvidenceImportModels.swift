import Foundation
import FoundationEvalsIntegration

enum EvaluationImportedSourceKind: String, Codable, Sendable {
    case captureBundle
    case appleEvaluationResult
    case appleTranscript
    case unsupportedJSON
}

struct EvaluationImportedCheck: Codable, Equatable, Sendable {
    var sampleID: UUID
    var name: String
    var status: String
    var label: String
    var rationale: String?
}

struct EvaluationImportedEvidence: Codable, Equatable, Sendable {
    var sourceKind: EvaluationImportedSourceKind
    var eligibility: String
    var producerAppID: String?
    var producerFeatureID: String?
    var producerRunID: String?
    var sourceDigest: String
    var manifestDigest: String?
    var importedAt: Date
    var captureStartedAt: Date?
    var captureEndedAt: Date?
    var warnings: [String]
    var coverageLabel: String
    var environmentClaims: [String: String]
    var importerHost: [String: String]
    var originalRelativePath: String
    var rerunOf: UUID?
    var sourceCaseIDs: [String: String]
    var transcriptAvailable: Bool
    var checks: [EvaluationImportedCheck]
}

enum EvaluationImportedLabels {
    static let notAssessed = "Output captured · Not assessed"
    static let producerCheckFailed = "Producer-reported check failed"
    static let ignoredCheck = "Check ignored · Not evidence of a pass"
    static let plannedUnknown = "Planned coverage unknown"
    static let transcriptMissing = "Transcript not captured"
    static let bareTranscript = "Saved conversation evidence · Feature rerun not connected"
    static let originalFileOnly = "Some fields are available only in the original file"
    static let incompleteCapture = "Incomplete capture · Some planned cases were not recorded"
    static let alreadyImported = "Already imported"
    static let conflict = "Conflicting evidence · Original preserved"
    static let inspectionOnly = "Inspection-only · Not a release pass"
}

struct EvidenceImportIndexRecord: Codable, Equatable, Sendable {
    var sourceKind: EvaluationImportedSourceKind
    var producerRunID: String?
    var sourceDigest: String
    var ownedRunID: UUID
    var suiteID: UUID
}

struct EvidenceImportIndex: Codable, Equatable, Sendable {
    var records: [EvidenceImportIndexRecord] = []
}

enum EvidenceImportOutcome: Equatable, Sendable {
    case readyToImport
    case alreadyImported(UUID)
    case conflict(UUID)
    case rejected
}

struct EvidenceImportPreview: Sendable {
    var destinationProjectID: UUID
    var destinationSuiteID: UUID
    var destinationProjectName: String
    var sourceKind: EvaluationImportedSourceKind
    var filename: String
    var warnings: [String]
    var coverageLabel: String
    var featureClaim: String
    var environmentSummary: String
    var sampleCount: Int
    var canNormalize: Bool
    var outcome: EvidenceImportOutcome
    var sourceDigest: String
    var producerRunID: String?
    var stagingRoot: URL
    var run: EvaluationRun
}

enum EvidenceImportError: LocalizedError, Equatable {
    case destinationChanged
    case destinationMissing
    case unsupportedContent(String)
    case unsafePath
    case cancelled

    var errorDescription: String? {
        switch self {
        case .destinationChanged: "The destination project changed before import was confirmed."
        case .destinationMissing: "The destination project or suite is no longer available."
        case .unsupportedContent(let message): message
        case .unsafePath: "The selected evidence contains an unsafe path."
        case .cancelled: "The import was cancelled."
        }
    }
}
