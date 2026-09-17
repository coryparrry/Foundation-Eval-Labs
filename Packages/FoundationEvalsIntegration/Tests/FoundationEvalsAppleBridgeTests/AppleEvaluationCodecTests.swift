import Evaluations
import Foundation
import FoundationEvalsAppleBridge
import FoundationEvalsIntegration
import Testing

struct AppleEvaluationCodecTests {
    @Test func evaluationsFrameworkIsImportable() {
        #expect(AppleEvaluationCodec.frameworkSearchHint.contains("Evaluations.framework"))
    }

    @Test func emptyJSONIsRejectedByNativeLoader() {
        #expect(throws: (any Error).self) {
            _ = try AppleEvaluationCodec.decodeResult(from: Data("{}".utf8))
        }
    }

    @Test func inspectRejectsJSONThatIsNotAnEvaluationResult() {
        #expect(throws: AppleEvaluationJSONError.notAnEvaluationResult) {
            _ = try AppleEvaluationJSONInspector.inspect(bytes: Data("{}".utf8))
        }
    }
}
