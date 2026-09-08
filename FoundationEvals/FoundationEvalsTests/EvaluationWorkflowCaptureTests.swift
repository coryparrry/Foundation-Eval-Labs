import Foundation
import FoundationModels
import Testing
@testable import FoundationEvals

struct EvaluationWorkflowCaptureTests {
    @Test func monotonicSpansPreserveHierarchyOverlapAndScoringDuration() throws {
        let origin = ContinuousClock.now
        let recorder = EvaluationWorkflowRecorder(origin: origin)
        let root = recorder.begin(kind: .sample, title: "Question", at: origin)
        let preparation = recorder.begin(kind: .preparation, title: "Prepare", parentID: root, at: origin)
        recorder.finish(preparation, at: origin.advanced(by: .milliseconds(10)))
        let generation = recorder.begin(kind: .generation, title: "Generate", parentID: root,
            at: origin.advanced(by: .milliseconds(10)))
        let first = recorder.begin(kind: .tool, title: "First", parentID: generation,
            at: origin.advanced(by: .milliseconds(12)))
        let second = recorder.begin(kind: .tool, title: "Second", parentID: generation,
            at: origin.advanced(by: .milliseconds(13)))
        recorder.finish(first, at: origin.advanced(by: .milliseconds(18)))
        recorder.finish(second, at: origin.advanced(by: .milliseconds(19)))
        recorder.finish(generation, at: origin.advanced(by: .milliseconds(30)))
        let scoring = recorder.begin(kind: .scoring, title: "Score", parentID: root,
            at: origin.advanced(by: .milliseconds(31)))
        recorder.finish(scoring, at: origin.advanced(by: .milliseconds(35)))
        recorder.finish(root, at: origin.advanced(by: .milliseconds(35)))

        let trace = try JSONDecoder().decode(EvaluationWorkflowTrace.self, from: JSONEncoder().encode(recorder.snapshot()))
        #expect(trace.spans.count == 6)
        #expect(trace.spans.first?.durationMilliseconds == 35)
        #expect(trace.spans.first(where: { $0.id == scoring })?.startOffsetMilliseconds == 31)
        #expect(trace.spans.first(where: { $0.id == first })?.durationMilliseconds == 6)
        #expect(trace.spans.first(where: { $0.id == second })?.startOffsetMilliseconds == 13)
        #expect(trace.spans.filter { $0.kind == .tool }.allSatisfy { $0.parentID == generation })
    }

    @Test func failureClosesOnlyOpenStagesAndKeepsSuccessfulStages() {
        let origin = ContinuousClock.now
        let recorder = EvaluationWorkflowRecorder(origin: origin)
        let root = recorder.begin(kind: .sample, title: "Cancelled sample", at: origin)
        let preparation = recorder.begin(kind: .preparation, title: "Prepare", parentID: root, at: origin)
        recorder.finish(preparation, at: origin.advanced(by: .milliseconds(3)))
        let generation = recorder.begin(kind: .generation, title: "Generate", parentID: root,
            at: origin.advanced(by: .milliseconds(3)))
        recorder.finishOpenSpans(status: .cancelled, errorMessage: "Cancelled", at: origin.advanced(by: .milliseconds(9)))
        let trace = recorder.snapshot()

        #expect(trace.spans.first(where: { $0.id == preparation })?.status == .succeeded)
        #expect(trace.spans.first(where: { $0.id == root })?.durationMilliseconds == 9)
        #expect(trace.spans.first(where: { $0.id == generation })?.durationMilliseconds == 6)
        #expect(trace.spans.first(where: { $0.id == generation })?.status == .cancelled)
        #expect(EvaluationWorkflowRecorder.status(for: URLError(.cancelled)) == .cancelled)
    }

    @Test func referenceCallsUseGenerationParentWithoutCapturingReferenceText() async throws {
        let workflow = EvaluationWorkflowRecorder()
        let generation = workflow.begin(kind: .generation, title: "Generate")
        workflow.activeParentID = generation
        let recorder = ReferenceToolRecorder(maximumCalls: 2, workflowRecorder: workflow)
        let tool = ReferenceLookupTool(index: ReferenceSearchIndex(attachments: [.init(
            id: UUID(), name: "Reference.txt", kind: .text, text: "The secret answer is ORCHARD.",
            storedFilename: nil, byteCount: 29, sha256: "fixture"
        )]), recorder: recorder)
        _ = try await tool.call(arguments: ReferenceLookupArguments(query: "secret answer", maximumResults: 1))
        await #expect(throws: (any Error).self) {
            _ = try await tool.call(arguments: ReferenceLookupArguments(query: "  ", maximumResults: 1))
        }
        workflow.finish(generation)
        let calls = workflow.snapshot().spans.filter { $0.kind == .tool }
        let encoded = String(decoding: try JSONEncoder().encode(workflow.snapshot()), as: UTF8.self)

        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.parentID == generation })
        #expect(calls.map(\.status) == [.succeeded, .failed])
        #expect(calls.map { $0.metadata["callIndex"] } == ["1", "2"])
        #expect(!encoded.contains("secret answer"))
        #expect(!encoded.contains("ORCHARD"))
    }

    @Test func wrappedFrameworkFailurePreservesTaskCancellation() async {
        let status = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return EvaluationWorkflowRecorder.status(for: URLError(.badServerResponse))
        }.value
        #expect(status == .cancelled)
    }

    @Test func fixtureToolLinksSavedCallAndDoesNotInventAnHTTPRequest() async throws {
        let workflow = EvaluationWorkflowRecorder()
        let generation = workflow.begin(kind: .generation, title: "Generate")
        workflow.activeParentID = generation
        let recorder = EvaluationCustomToolRecorder(maximumCalls: 1, workflowRecorder: workflow)
        let tool = try EvaluationCustomTool(definition: .init(name: "fixture_tool", description: "Fixture", fixtureResponse: "ok"),
            recorder: recorder, httpClient: WorkflowCancelledClient(), tokenCounter: WorkflowFixedTokenCounter())
        _ = try await tool.call(arguments: GeneratedContent(kind: .structure(properties: [:], orderedKeys: [])))
        let savedCall = try #require(await recorder.snapshot().first)
        let span = try #require(workflow.snapshot().spans.first(where: { $0.kind == .tool }))

        #expect(span.parentID == generation)
        #expect(span.metadata["callID"] == savedCall.id.uuidString)
        #expect(span.status == .succeeded)
        #expect(!workflow.snapshot().spans.contains { $0.kind == .httpRequest })
    }

    @Test func cancelledToolRemainsCancelledInBothRecordings() async throws {
        let workflow = EvaluationWorkflowRecorder()
        workflow.activeParentID = workflow.begin(kind: .generation, title: "Generate")
        let recorder = EvaluationCustomToolRecorder(maximumCalls: 1, workflowRecorder: workflow)
        let tool = try EvaluationCustomTool(definition: .init(name: "cancelled_tool", description: "Cancellation fixture",
            mode: .localHTTP, endpoint: "http://127.0.0.1:19090/run"), recorder: recorder,
            httpClient: WorkflowCancelledClient(), tokenCounter: WorkflowFixedTokenCounter())
        await #expect(throws: CancellationError.self) {
            _ = try await tool.call(arguments: GeneratedContent(kind: .structure(properties: [:], orderedKeys: [])))
        }
        #expect(await recorder.snapshot().first?.outcome == .cancelled)
        #expect(workflow.snapshot().spans.first(where: { $0.kind == .tool })?.status == .cancelled)
        #expect(!workflow.snapshot().spans.contains { $0.kind == .httpRequest })
    }

    @Test func rejectedToolSpansLinkTheirSavedArgumentsAndRespectRejectionCaptureLimit() async throws {
        let workflow = EvaluationWorkflowRecorder()
        let generation = workflow.begin(kind: .generation, title: "Generate")
        workflow.activeParentID = generation
        let recorder = EvaluationCustomToolRecorder(maximumCalls: 1, workflowRecorder: workflow)
        let tool = try EvaluationCustomTool(definition: .init(name: "limited_tool", description: "Bounded fixture",
            parameters: [.init(name: "query")], fixtureResponse: "ok"), recorder: recorder,
            httpClient: WorkflowCancelledClient(), tokenCounter: WorkflowFixedTokenCounter())
        _ = try await tool.call(arguments: GeneratedContent(properties: ["query": "allowed request"]))
        for attempt in 1...6 {
            await #expect(throws: EvaluationCustomToolError.self) {
                _ = try await tool.call(arguments: GeneratedContent(properties: ["query": "rejected request \(attempt)"]))
            }
        }

        let recordedCalls = await recorder.snapshot()
        let spans = workflow.snapshot().spans.filter { $0.kind == .tool }
        #expect(recordedCalls.count == 5)
        #expect(recordedCalls.first?.outcome == .succeeded)
        #expect(recordedCalls.filter { $0.outcome == .rejected }.count == 4)
        #expect(spans.count == 7)
        #expect(Set(recordedCalls.map(\.id)).count == recordedCalls.count)
        for rejectedCall in recordedCalls.dropFirst() {
            let span = try #require(spans.first { $0.metadata["callID"] == rejectedCall.id.uuidString })
            #expect(span.parentID == generation)
            #expect(span.status == .failed)
            #expect(span.errorMessage == rejectedCall.errorDescription)
            #expect(rejectedCall.argumentsJSON.contains("rejected request"))
        }
        let firstRejectedSpan = try #require(spans.first { $0.status == .failed })
        let selectedEvidence = try #require(recordedCalls.first { $0.id.uuidString == firstRejectedSpan.metadata["callID"] })
        #expect(selectedEvidence.argumentsJSON.contains("rejected request 1"))
        #expect(selectedEvidence.errorDescription?.contains("1-call custom tool limit") == true)
    }

    @Test(arguments: [200, 503, -999])
    func realHTTPClientRecordsStatusBytesAndCancellationWithoutPayloads(_ status: Int) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkflowHTTPProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = EvaluationLocalHTTPToolClient(session: session)
        let workflow = EvaluationWorkflowRecorder()
        let parent = workflow.begin(kind: .tool, title: "HTTP tool")
        let endpoint = try #require(URL(string: "http://127.0.0.1:19090/\(status)"))
        do {
            _ = try await EvaluationWorkflowHTTPContext.$current.withValue(.init(recorder: workflow, parentID: parent)) {
                try await client.post(body: Data("private-request".utf8), to: endpoint)
            }
            #expect(status == 200)
        } catch {
            #expect(status != 200)
        }
        let span = try #require(workflow.snapshot().spans.first(where: { $0.kind == .httpRequest }))
        let encoded = String(decoding: try JSONEncoder().encode(span), as: UTF8.self)
        #expect(span.parentID == parent)
        #expect(span.metadata["method"] == "POST")
        #expect(span.metadata["requestBytes"] == "15")
        #expect(span.durationMilliseconds >= 0)
        #expect(!encoded.contains("private-request"))
        #expect(!encoded.contains("private-response"))
        if status == -999 {
            #expect(span.status == .cancelled)
            #expect(span.metadata["statusCode"] == nil)
        } else {
            #expect(span.metadata["statusCode"] == String(status))
            #expect(span.status == (status == 200 ? .succeeded : .failed))
            #expect(span.metadata["responseBytes"] == (status == 200 ? "16" : "0"))
        }
    }

    @Test func endpointsExcludeCredentialsQueriesAndFragments() throws {
        let endpoint = try #require(URL(string: "http://username:secret@127.0.0.1:19090/run?token=credential#private"))
        #expect(EvaluationWorkflowHTTPRequest.sanitizedEndpoint(endpoint) == "http://127.0.0.1:19090/run")
    }
}

private struct WorkflowFixedTokenCounter: EvaluationCustomToolTokenCounting {
    func tokenCount(for text: String) async throws -> Int { 1 }
}

private struct WorkflowCancelledClient: EvaluationCustomToolHTTPClient {
    func post(body: Data, to endpoint: URL) async throws -> String { throw CancellationError() }
}

private final class WorkflowHTTPProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let status = Int(url.lastPathComponent) else { return }
        if status == -999 {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("private-response".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
