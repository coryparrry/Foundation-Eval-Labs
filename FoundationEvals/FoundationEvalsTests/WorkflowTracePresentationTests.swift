import Foundation
import Testing
@testable import FoundationEvals

struct WorkflowTracePresentationTests {
    @Test func legacyDurationsNeverAcquireTimelineOffsets() throws {
        var sample = try fixture()
        sample.timing = EvaluationSampleTiming(preparationMilliseconds: 10, generationMilliseconds: 20, scoringMilliseconds: 5)
        let trace = WorkflowTracePresentation(result: sample)
        #expect(!trace.hasMeasuredOffsets)
        #expect(trace.nodes.allSatisfy { $0.startMilliseconds == nil && $0.endMilliseconds == nil })
        #expect(trace.nodes.first?.durationMilliseconds == nil) // Subject latency excludes scoring.
        #expect(trace.nodes.first(where: { $0.kind == .generation })?.durationMilliseconds == 20)
    }

    @Test func nestedOverlappingSpansShareOneAxisAndCollapseTogether() throws {
        var sample = try fixture()
        let root = span(.sample, start: 0, duration: 120)
        let generation = span(.generation, parent: root.id, start: 10, duration: 100)
        let first = span(.tool, parent: generation.id, start: 20, duration: 60)
        let second = span(.tool, parent: generation.id, start: 30, duration: 70)
        let scoring = span(.scoring, parent: root.id, start: 110, duration: 10)
        sample.workflowTrace = EvaluationWorkflowTrace(spans: [root, generation, first, second, scoring])
        let trace = WorkflowTracePresentation(result: sample)
        #expect(trace.extentMilliseconds == 120)
        #expect(trace.visibleRows(collapsed: []).map(\.depth) == [0, 1, 2, 2, 1])
        #expect(trace.visibleRows(collapsed: [generation.id.uuidString]).map(\.id) ==
            [root.id, generation.id, scoring.id].map(\.uuidString))
        #expect(trace.nodes[2].startMilliseconds == 20)
        #expect(trace.nodes[3].endMilliseconds == 100)
    }

    @Test func cancelledAndFailedSpansRetainDistinctOutcomes() throws {
        var sample = try fixture()
        var cancelled = span(.generation, start: 4, duration: 9)
        cancelled.status = .cancelled
        cancelled.errorMessage = "Cancelled by user"
        var failed = span(.tool, parent: cancelled.id, start: 6, duration: 2)
        failed.status = .failed
        sample.workflowTrace = EvaluationWorkflowTrace(spans: [cancelled, failed])
        let trace = WorkflowTracePresentation(result: sample)
        #expect(trace.nodes[0].outcome == "cancelled")
        #expect(trace.nodes[0].errorMessage == "Cancelled by user")
        #expect(trace.nodes[1].outcome == "failed")
        #expect(trace.nodes.allSatisfy { $0.hasIssue })
    }

    @Test func builtInTranscriptToolsHaveContentIdentityButNoInventedTiming() throws {
        var sample = try fixture()
        let generation = span(.generation, start: 1, duration: 20)
        sample.workflowTrace = EvaluationWorkflowTrace(spans: [generation])
        sample.featureTrace = EvaluationFeatureTrace(builtinToolCalls: [
            EvaluationBuiltinToolTrace(id: "vision-call", toolName: "read_image", argumentsJSON: "{}", output: "Image evidence")
        ])
        let trace = WorkflowTracePresentation(result: sample)
        let tool = try #require(trace.nodes.last)
        #expect(tool.parentID == nil) // Transcript aggregation does not identify the generating turn.
        #expect(tool.startMilliseconds == nil)
        #expect(tool.durationMilliseconds == nil)
        #expect(tool.outcome == "recorded")
        #expect(tool.metadata["callID"] == "vision-call")
    }

    @Test func malformedImportsRemainInspectableWithoutInvalidGeometry() throws {
        var sample = try fixture()
        var first = span(.sample, start: .nan, duration: -1)
        var second = span(.generation, parent: first.id, start: 2, duration: .infinity)
        first.parentID = second.id
        second.errorMessage = "Fixture cycle"
        sample.workflowTrace = EvaluationWorkflowTrace(spans: [first, second, first])
        let trace = WorkflowTracePresentation(result: sample)
        #expect(trace.nodes.count == 2)
        #expect(trace.visibleRows(collapsed: []).count == 2)
        #expect(trace.extentMilliseconds == 1)
        #expect(trace.nodes.allSatisfy { $0.endMilliseconds == nil })
        #expect(WorkflowTracePresentation.duration(.nan) == "—")
    }

    @Test func largeFlatTracePreservesEverySpanAndStableSelectionIdentity() throws {
        var sample = try fixture()
        let root = span(.sample, start: 0, duration: 1_001)
        let children = (0..<1_000).map { span(.tool, parent: root.id, start: Double($0), duration: 1) }
        sample.workflowTrace = EvaluationWorkflowTrace(spans: [root] + children)
        let trace = WorkflowTracePresentation(result: sample)
        #expect(trace.visibleRows(collapsed: []).count == 1_001)
        #expect(trace.visibleRows(collapsed: [root.id.uuidString]).count == 1)
        #expect(trace.nodes.last?.id == children.last?.id.uuidString)
    }

    @Test func legacyAggregateToolCallsStayAtSampleScope() throws {
        var sample = try fixture()
        sample.featureTrace = EvaluationFeatureTrace(customToolCalls: [EvaluationCustomToolCallTrace(
            id: UUID(), toolName: "setup_tool", argumentsJSON: "{}", output: "ready",
            durationMilliseconds: 3, outcome: .succeeded, errorDescription: nil)])
        sample.toolCalls = [EvaluationToolCallTrace(toolName: "search_reference_files", callIndex: 1,
            matchedFiles: [], outputCharacterCount: 4, outcome: "completed")]
        let calls = WorkflowTracePresentation(result: sample).nodes.filter { $0.kind == .tool }
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.parentID == "sample" && $0.metadata["scope"] != nil })
    }

    @Test func failedGenerationDoesNotInheritSetupSessionTokens() throws {
        var sample = try fixture()
        sample.errorCategory = "cancelled"
        sample.usage = EvaluationUsage(inputTokens: 100, outputTokens: 20)
        var generation = span(.generation, start: 3, duration: 5)
        generation.status = .cancelled
        generation.metadata = ["role": "evaluation"]
        sample.workflowTrace = EvaluationWorkflowTrace(spans: [generation])
        let node = try #require(WorkflowTracePresentation(result: sample).nodes.first)
        #expect(node.usage(in: sample, measured: true) == nil)
        #expect(node.usage(in: sample, measured: false) == nil)
        generation.metadata.merge(["inputTokens": "8", "outputTokens": "2"]) { _, new in new }
        sample.workflowTrace = EvaluationWorkflowTrace(spans: [generation])
        let measuredNode = try #require(WorkflowTracePresentation(result: sample).nodes.first)
        #expect(measuredNode.usage(in: sample, measured: true)?.totalTokens == 10)
    }

    @Test func legacyGenerationUsesTurnUsageRatherThanSessionTotals() throws {
        var sample = try fixture()
        sample.usage = EvaluationUsage(inputTokens: 100, outputTokens: 20)
        let generation = try #require(WorkflowTracePresentation(result: sample).nodes.first(where: { $0.kind == .generation }))
        #expect(generation.usage(in: sample, measured: false) == nil)
        sample.featureTrace = EvaluationFeatureTrace(conversation: EvaluationConversationTrace(turns: [
            EvaluationConversationTurnTrace(id: UUID(), kind: .evaluation, prompt: "Question", response: "Answer",
                durationMilliseconds: 20, usage: EvaluationUsage(inputTokens: 8, outputTokens: 2))
        ]))
        #expect(generation.usage(in: sample, measured: false)?.totalTokens == 10)
    }

    private func span(_ kind: EvaluationWorkflowSpanKind, parent: UUID? = nil, start: Double, duration: Double) -> EvaluationWorkflowSpan {
        EvaluationWorkflowSpan(id: UUID(), parentID: parent, kind: kind, title: "Test \(kind.rawValue)",
            startOffsetMilliseconds: start, durationMilliseconds: duration, status: .succeeded)
    }

    private func fixture() throws -> EvaluationSampleResult {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","caseID":"00000000-0000-0000-0000-000000000002",
         "caseName":"Trace presentation test","repetition":1,"prompt":"Question","expected":"Answer","response":"Answer",
         "status":"passed","durationMilliseconds":30,"usage":{"inputTokens":3,"outputTokens":1,"cachedInputTokens":0,"reasoningTokens":0}}
        """
        return try JSONDecoder().decode(EvaluationSampleResult.self, from: Data(json.utf8))
    }
}
