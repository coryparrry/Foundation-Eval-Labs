import Evaluations
import Foundation
import FoundationEvalsIntegration

public struct AppleEvaluationSampleInspection: Sendable, Equatable {
    public var index: Int
    public var fields: [String: String]
    public var subjectError: String?
    public var evaluatorError: String?

    public init(index: Int, fields: [String: String], subjectError: String?, evaluatorError: String?) {
        self.index = index
        self.fields = fields
        self.subjectError = subjectError
        self.evaluatorError = evaluatorError
    }
}

public struct AppleEvaluationInspection: Sendable, Equatable {
    public var resultID: UUID
    public var evaluationID: String
    public var evaluationInfo: [String: String]
    public var startedAt: Date
    public var endedAt: Date
    public var inferenceFailureCount: Int
    public var evaluatorFailureCount: Int
    public var failingEvaluatorTypes: [String]
    public var metricsNotFound: [String]
    public var rowCount: Int
    public var columnNames: [String]
    public var samples: [AppleEvaluationSampleInspection]
    public var originalByteCount: Int
    public var digest: String
    public var warnings: [String]

    public init(
        resultID: UUID,
        evaluationID: String,
        evaluationInfo: [String: String],
        startedAt: Date,
        endedAt: Date,
        inferenceFailureCount: Int,
        evaluatorFailureCount: Int,
        failingEvaluatorTypes: [String],
        metricsNotFound: [String],
        rowCount: Int,
        columnNames: [String],
        samples: [AppleEvaluationSampleInspection],
        originalByteCount: Int,
        digest: String,
        warnings: [String]
    ) {
        self.resultID = resultID
        self.evaluationID = evaluationID
        self.evaluationInfo = evaluationInfo
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.inferenceFailureCount = inferenceFailureCount
        self.evaluatorFailureCount = evaluatorFailureCount
        self.failingEvaluatorTypes = failingEvaluatorTypes
        self.metricsNotFound = metricsNotFound
        self.rowCount = rowCount
        self.columnNames = columnNames
        self.samples = samples
        self.originalByteCount = originalByteCount
        self.digest = digest
        self.warnings = warnings
    }
}

@available(macOS 27, *)
extension AppleEvaluationCodec {
    public static func inspect(bytes: Data) throws -> AppleEvaluationInspection {
        let result = try decodeResult(from: bytes)
        let warnings = [
            "Planned coverage unknown",
            "Per-trial crash recovery is unavailable for this native export unless the producer recorded observations around each subject call.",
            "Some fields are available only in the original file",
            "Check ignored · Not evidence of a pass",
        ]
        return AppleEvaluationInspection(
            resultID: result.resultID,
            evaluationID: result.evaluationID,
            evaluationInfo: result.evaluationInfo,
            startedAt: result.startTime,
            endedAt: result.endTime,
            inferenceFailureCount: result.errors.inferenceFailureCount,
            evaluatorFailureCount: result.errors.evaluatorFailureCount,
            failingEvaluatorTypes: result.errors.failingEvaluatorTypes.sorted(),
            metricsNotFound: result.errors.metricsNotFound,
            rowCount: 0,
            columnNames: [],
            samples: [],
            originalByteCount: bytes.count,
            digest: CaptureDigest.sha256Hex(bytes),
            warnings: warnings
        )
    }
}
