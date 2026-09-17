import Evaluations
import Foundation

/// Compile-time and link-time proof that the workbench links Xcode's Evaluations framework.
@available(macOS 27, *)
enum EvaluationsFrameworkAvailability {
    static func decodeResult(from jsonData: Data) throws -> EvaluationResult {
        try EvaluationResult(jsonData: jsonData)
    }
}
