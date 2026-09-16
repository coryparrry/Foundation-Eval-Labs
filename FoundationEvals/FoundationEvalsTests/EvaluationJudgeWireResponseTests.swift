import Foundation
import Testing
@testable import FoundationEvals

struct EvaluationJudgeWireResponseTests {
    @Test(arguments: [false, true])
    func explicitErrorWinsOverValidContentAndMalformedUsage(afterContent: Bool) throws {
        var events = afterContent ? [try event(["choices": [["delta": ["content": "valid-looking verdict"]]]])] : []
        events.append(try event(["error": ["message": "provider failed"], "usage": []]))
        let data = Data((events.joined() + "data: [DONE]\n\n").utf8)
        #expect(throws: EvaluationJudgeWireFailure.self) {
            try EvaluationJudgeWireResponse.decode(from: data)
        }
    }

    @Test(arguments: ["length", "content_filter", "error", "tool_calls", "unknown_failure"])
    func explicitNonSuccessStatusIsNotACompleteVerdict(reason: String) throws {
        let data = Data(try event(["choices": [["delta": ["content": "{}"], "finish_reason": reason]]]).utf8)
        #expect(throws: EvaluationJudgeWireFailure.self) { try EvaluationJudgeWireResponse.decode(from: data) }
    }

    @Test(arguments: ["[]", "\"unavailable\"", "null", "{}", "{\"prompt_tokens\":10}",
                      "{\"prompt_tokens\":-1,\"completion_tokens\":5}",
                      "{\"prompt_tokens\":1e100,\"completion_tokens\":5}"])
    func optionalUsageHasTheSameBestEffortBoundaryInJSONAndSSE(usage: String) throws {
        let json = "{\"choices\":[{\"message\":{\"content\":\"verdict\"}}],\"usage\":\(usage)}"
        let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"verdict\"}}],\"usage\":\(usage)}\n\ndata: [DONE]\n\n"
        for body in [json, sse] {
            let response = try EvaluationJudgeWireResponse.decode(from: Data(body.utf8))
            #expect(response.choices.first?.message.content == "verdict")
            #expect(response.usage?.evaluationUsage == nil)
            #expect(response.usage?.reportedCost == nil)
        }
    }

    @Test func validUsageSurvivesAnInvalidTrailerAndKeepsReportedCost() throws {
        let first = try event(["choices": [["delta": ["content": "verdict"]]],
                               "usage": ["prompt_tokens": 10, "completion_tokens": 5, "cost": 0.02]])
        let trailer = try event(["choices": [], "usage": []])
        let result = try EvaluationJudgeWireResponse.decode(from: Data((first + trailer + "data: [DONE]\n\n").utf8))
        #expect(result.usage?.evaluationUsage?.inputTokens == 10)
        #expect(result.usage?.evaluationUsage?.outputTokens == 5)
        #expect(result.usage?.reportedCost == 0.02)
    }

    @Test func completeUsageOnlyTrailerIsAccepted() throws {
        let body = try event(["choices": [["delta": ["content": "verdict"], "finish_reason": "stop"]]])
            + event(["choices": [], "usage": ["prompt_tokens": 10, "completion_tokens": 5]])
        let result = try EvaluationJudgeWireResponse.decode(from: Data(body.utf8))
        #expect(result.usage?.evaluationUsage?.inputTokens == 10)
        #expect(result.choices.first?.message.content == "verdict")
    }

    @Test func optionalTelemetryDoesNotMakeRequiredProtocolFieldsLossy() throws {
        #expect(throws: DecodingError.self) {
            try EvaluationJudgeWireResponse.decode(from: Data("data: {\"choices\":\"wrong\",\"usage\":[]}\n\n".utf8))
        }
        #expect(throws: EvaluationJudgeWireFailure.self) {
            try EvaluationJudgeWireResponse.decode(from: Data("{\"error\":[],\"usage\":[]}".utf8))
        }
        #expect(throws: EvaluationJudgeWireFailure.self) {
            try EvaluationJudgeWireResponse.decode(from: Data("data: {\"choices\":[{\"index\":1,\"delta\":{\"content\":\"wrong choice\"}}]}\n\n".utf8))
        }
    }

    private func event(_ object: [String: Any]) throws -> String {
        "data: " + String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n\n"
    }
}
