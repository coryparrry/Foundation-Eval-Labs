import Evaluations
import Foundation

/// Native Apple evaluation-result codec. Requires Xcode's Evaluations framework.
@available(macOS 27, *)
public enum AppleEvaluationCodec: Sendable {
    public static let frameworkSearchHint = "Xcode Developer Library: Platforms/MacOSX.platform/Developer/Library/Frameworks/Evaluations.framework"

    public static func decodeResult(from jsonData: Data) throws -> EvaluationResult {
        try EvaluationResult(jsonData: jsonData)
    }

    public static func loadResult(from url: URL) throws -> EvaluationResult {
        try EvaluationResult.loadJSON(from: url)
    }
}
