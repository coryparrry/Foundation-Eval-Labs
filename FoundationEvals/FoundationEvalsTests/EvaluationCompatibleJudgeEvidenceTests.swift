import Foundation
import Network
import Testing
@testable import FoundationEvals

@Suite(.timeLimit(.minutes(1)))
struct EvaluationCompatibleJudgeEvidenceTests {
    @Test func persistedPolicyAndMessagesMatchTheActualHTTPRequest() async throws {
        let fixture = try JudgeEvidenceHTTPFixture(bodies: [try envelope(verdict)])
        defer { fixture.stop() }
        let connection = connection(for: fixture)
        let result = try await judge(connection: connection, apiKey: "fixture-secret-not-for-traces")
        let request = try #require(fixture.bodies.first)
        let messages = try wireMessages(request)
        #expect(result.trace.instructions == messages[0])
        #expect(result.trace.prompt == messages[1])
        #expect(result.trace.instructions != EvaluationRunner.judgeInstructions)
        #expect(result.trace.policyVersion == EvaluationCompatibleJudgeClient.policyVersion)
        let attempt = try #require(result.trace.attempts?.first)
        #expect(attempt.instructions == messages[0])
        #expect(attempt.prompt == messages[1])
        #expect(attempt.policyVersion == result.trace.policyVersion)
        let data = try JSONEncoder().encode(result.trace)
        #expect(!String(decoding: data, as: UTF8.self).contains("fixture-secret-not-for-traces"))
        let restored = try JSONDecoder().decode(EvaluationJudgeTrace.self, from: data)
        #expect(restored.instructions == messages[0])
        #expect(restored.policyVersion == result.trace.policyVersion)
        let contract = try EvaluationScoringContract(suite: approvedSuite(connection))
        var oldContract = contract
        oldContract.judgePromptVersion = "rubric-v7-required-assessments"
        #expect(contract != oldContract)
        #expect(contract.judgePromptVersion == EvaluationRunner.judgePromptVersion)
        #expect(fixture.bodies.count == 1)
    }

    @Test func malformedMessageContentSurvivesBothRepairAttemptsAndTracePersistence() async throws {
        let invalid = ["first response is not JSON", "{ second response is broken"]
        let fixture = try JudgeEvidenceHTTPFixture(bodies: invalid.map { try envelope($0) })
        defer { fixture.stop() }
        do {
            _ = try await judge(connection: connection(for: fixture), apiKey: "secret-not-in-evidence")
            Issue.record("Malformed content must not produce a judgment.")
        } catch let error as EvaluationCompatibleJudgeError {
            guard case .exhausted(_, let attempts) = error else {
                Issue.record("Expected bounded repair exhaustion, received \(error).")
                return
            }
            #expect(attempts.compactMap(\.rawResponse) == invalid)
            #expect(attempts.count == 2)
            #expect(fixture.bodies.count == 2)
            for (attempt, body) in zip(attempts, fixture.bodies) {
                let messages = try wireMessages(body)
                #expect(attempt.instructions == messages[0])
                #expect(attempt.prompt == messages[1])
                #expect(attempt.validationError != nil)
                #expect((attempt.rawResponse?.utf8.count ?? 0) <= EvaluationCompatibleJudgeClient.maximumResponseBytes)
            }
            let trace = try #require(EvaluationRunner.externalJudgeFailureTrace(error,
                completedChecks: [], judgedCriterionIndexes: [1]))
            let data = try JSONEncoder().encode(trace)
            #expect(!String(decoding: data, as: UTF8.self).contains("secret-not-in-evidence"))
            let restored = try JSONDecoder().decode(EvaluationJudgeTrace.self, from: data)
            #expect(restored.attempts?.compactMap(\.rawResponse) == invalid)
            #expect(restored.instructions == attempts.last?.instructions)
            #expect(restored.policyVersion == EvaluationCompatibleJudgeClient.policyVersion)
            #expect(restored.rawResponse == invalid[1])
        }
    }

    @Test(arguments: [false, true])
    func providerStreamErrorsAreNotRepairedAndRetainFailureEvidence(afterContent: Bool) async throws {
        let prefix = afterContent ? try event(["choices": [["delta": ["content": verdict]]]]) : ""
        let errorEvent = try event(["error": ["message": "upstream overloaded"], "usage": []])
        let body = Data((prefix + errorEvent + "data: [DONE]\n\n").utf8)
        let fixture = try JudgeEvidenceHTTPFixture(bodies: [body], contentType: "text/event-stream")
        defer { fixture.stop() }
        do {
            _ = try await judge(connection: connection(for: fixture, streaming: true))
            Issue.record("An explicit provider error must win over verdict content.")
        } catch let failure as EvaluationJudgeWireFailure {
            #expect(failure.kind == .providerError)
            #expect(failure.attempts.count == 1)
            #expect(failure.attempts.first?.rawResponse == String(decoding: body, as: UTF8.self))
            #expect(EvaluationRunner.externalJudgeErrorCategory(failure) == "serviceUnavailable")
            #expect(EvaluationRunner.stopsBatch(for: EvaluationRunner.externalJudgeErrorCategory(failure)))
            let trace = try #require(EvaluationRunner.externalJudgeFailureTrace(failure,
                completedChecks: [], judgedCriterionIndexes: [1]))
            #expect(trace.validationError?.contains("upstream overloaded") == true)
            let request = try #require(fixture.bodies.first)
            #expect(trace.instructions == (try wireMessages(request))[0])
            #expect(trace.policyVersion == EvaluationCompatibleJudgeClient.policyVersion)
        }
        #expect(fixture.bodies.count == 1)
    }

    @Test(arguments: ["length", "content_filter", "error"])
    func unsuccessfulStreamTerminationDoesNotSpendARepairRequest(reason: String) async throws {
        let body = try event(["choices": [["delta": ["content": verdict]]]])
            + event(["choices": [["delta": [:], "finish_reason": reason]]]) + "data: [DONE]\n\n"
        let fixture = try JudgeEvidenceHTTPFixture(bodies: [Data(body.utf8)], contentType: "text/event-stream")
        defer { fixture.stop() }
        do {
            _ = try await judge(connection: connection(for: fixture, streaming: true))
            Issue.record("The provider did not complete its verdict.")
        } catch let failure as EvaluationJudgeWireFailure {
            #expect(failure.kind == .incompleteCompletion)
            #expect(failure.attempts.count == 1)
            #expect(EvaluationRunner.externalJudgeErrorCategory(failure) == "invalidJudgeOutput")
        }
        #expect(fixture.bodies.count == 1)
    }

    @Test(arguments: ["[]", "\"bad telemetry\"", "null", "{}", "{\"prompt_tokens\":10}"])
    func malformedSSEUsageDoesNotDiscardOrRetryAValidVerdict(usage: String) async throws {
        let first = try event(["choices": [["delta": ["content": verdict], "finish_reason": "stop"]]])
        let body = first + "data: {\"choices\":[],\"usage\":\(usage)}\n\ndata: [DONE]\n\n"
        let fixture = try JudgeEvidenceHTTPFixture(bodies: [Data(body.utf8)], contentType: "text/event-stream")
        defer { fixture.stop() }
        let result = try await judge(connection: connection(for: fixture, streaming: true))
        #expect(result.judgment.score == 4)
        #expect(result.usage == nil)
        #expect(result.cost.availability == .unavailable)
        #expect(result.trace.attempts?.count == 1)
        #expect(fixture.bodies.count == 1)
    }

    @Test func legacyAttemptDoesNotAcquireInventedInstructionsOrPolicy() throws {
        let old = Data("{\"prompt\":\"old request\",\"rawResponse\":\"not JSON\"}".utf8)
        let attempt = try JSONDecoder().decode(EvaluationJudgeAttemptTrace.self, from: old)
        #expect(attempt.instructions == nil)
        #expect(attempt.policyVersion == nil)
        let trace = try #require(EvaluationRunner.externalJudgeFailureTrace(
            EvaluationCompatibleJudgeError.exhausted(message: "invalid", attempts: [attempt]),
            completedChecks: [], judgedCriterionIndexes: [1]))
        #expect(trace.instructions.isEmpty)
        #expect(trace.policyVersion == nil)
    }

    private var verdict: String {
        #"{"requirements":[{"criterionIndex":1,"score":4,"rationale":"Supported by the answer."}]}"#
    }
    private func envelope(_ content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
    }
    private func event(_ object: [String: Any]) throws -> String {
        "data: " + String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n\n"
    }
    private func wireMessages(_ data: Data) throws -> [String] {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: Any]])
        let strings = messages.compactMap { $0["content"] as? String }
        try #require(strings.count == 2)
        return strings
    }
    private func connection(for fixture: JudgeEvidenceHTTPFixture, streaming: Bool = false) -> EvaluationJudgeConnection {
        EvaluationJudgeConnection(id: UUID(), name: "Evidence fixture", kind: .localCompatible,
            baseURL: fixture.baseURL, modelID: streaming ? "deepseek-fixture" : "fixture")
    }
    private func approvedSuite(_ connection: EvaluationJudgeConnection) -> EvaluationSuite {
        var suite = EvaluationSuite()
        suite.criteria = "The answer is supported."
        suite.judgeConfiguration = .init(mode: .connection, connectionID: connection.id,
            externalEvidenceApprovedAt: Date(), includeReferenceAttachments: false,
            approvedConnectionID: connection.id, approvedIncludeReferenceAttachments: false,
            approvedConnectionDigest: connection.disclosureDigest)
        return suite
    }
    private func judge(connection: EvaluationJudgeConnection, apiKey: String? = nil) async throws -> EvaluationCompatibleJudgeResult {
        let suite = approvedSuite(connection)
        return try await EvaluationCompatibleJudgeClient().judge(response: "Response", evaluationCase: suite.cases[0],
            effectivePrompt: "Prompt", suite: suite, images: [], toolEvidence: nil,
            resolved: .init(connection: connection, apiKey: apiKey))
    }
}

/// A bounded loopback fixture with deterministic response order and request-body
/// capture. Awaiting the client is the completion signal; no polling deadlines.
private final class JudgeEvidenceHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "JudgeEvidenceHTTPFixture")
    private let lock = NSLock()
    private var requests: [Data] = []
    private var connections: [NWConnection] = []
    private let replies: [Data]
    private let contentType: String
    private(set) var port: UInt16 = 0
    var baseURL: String { "http://127.0.0.1:\(port)/v1" }
    var bodies: [Data] { lock.withLock { requests } }

    init(bodies: [Data], contentType: String = "application/json") throws {
        precondition(!bodies.isEmpty)
        replies = bodies
        self.contentType = contentType
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.port = self?.listener.port?.rawValue ?? 0
                ready.signal()
            case .failed: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.lock.withLock { self.connections.append(connection) }
            connection.start(queue: self.queue)
            self.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, port != 0 else {
            listener.cancel()
            throw CocoaError(.fileReadUnknown)
        }
    }

    func stop() {
        listener.cancel()
        let active = lock.withLock { let active = connections; connections.removeAll(); return active }
        active.forEach { $0.cancel() }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= 256 * 1_024 else { connection.cancel(); return }
            if let separator = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headers = String(decoding: buffer[..<separator.lowerBound], as: UTF8.self)
                let length = headers.components(separatedBy: "\r\n").compactMap { line -> Int? in
                    guard line.lowercased().hasPrefix("content-length:") else { return nil }
                    return Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
                }.first ?? 0
                guard length >= 0, length <= 256 * 1_024 else { connection.cancel(); return }
                if buffer.count - separator.upperBound >= length {
                    let body = Data(buffer[separator.upperBound..<(separator.upperBound + length)])
                    let index = self.lock.withLock { self.requests.append(body); return self.requests.count - 1 }
                    let reply = self.replies[min(index, self.replies.count - 1)]
                    let header = "HTTP/1.1 200 OK\r\nContent-Type: \(self.contentType)\r\nContent-Length: \(reply.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(header.utf8) + reply, completion: .contentProcessed { _ in connection.cancel() })
                    return
                }
            }
            guard !complete else { connection.cancel(); return }
            self.receive(connection, buffer: buffer)
        }
    }
}
