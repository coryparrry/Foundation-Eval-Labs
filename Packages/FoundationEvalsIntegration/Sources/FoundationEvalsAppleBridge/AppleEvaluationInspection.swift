import Evaluations
import Foundation
import FoundationEvalsIntegration
import TabularData

@available(macOS 27, *)
extension AppleEvaluationCodec {
    public static func inspect(bytes: Data) throws -> AppleEvaluationInspection {
        let result = try decodeResult(from: bytes)
        var inspection = try AppleEvaluationJSONInspector.inspect(bytes: bytes)
        inspection.resultID = result.resultID
        inspection.evaluationID = result.evaluationID
        inspection.evaluationInfo = result.evaluationInfo
        inspection.startedAt = result.startTime
        inspection.endedAt = result.endTime
        inspection.inferenceFailureCount = result.errors.inferenceFailureCount
        inspection.evaluatorFailureCount = result.errors.evaluatorFailureCount
        inspection.failingEvaluatorTypes = result.errors.failingEvaluatorTypes.sorted()
        inspection.metricsNotFound = result.errors.metricsNotFound
        let detailedRows = result.detailed.shape.rows
        if inspection.samples.isEmpty, detailedRows > 0 {
            inspection.warnings.insert(AppleEvaluationInspectionLabels.metadataOnly, at: 0)
            inspection.rowCount = detailedRows
        } else if inspection.samples.count != detailedRows {
            inspection.warnings.append(
                "Native detailed row count (\(detailedRows)) differs from converted samples (\(inspection.samples.count))."
            )
        }
        return inspection
    }
}
