import Foundation
import Network
import Testing
@testable import FoundationEvals

struct EvaluationCompatibleJudgeClientTests {
    @Test(.timeLimit(.minutes(1)))
    func fixtureChecksCapabilitiesAndReturnsValidatedProvenance() async throws {
        let fixture = try CompatibleJudgeFixture(mode: .valid)
        defer { fixture.stop() }
        let connection = EvaluationJudgeConnection(
            id: UUID(), name: "Fixture judge", kind: .localCompatible,
            baseURL: fixture.baseURL, modelID: "judge-fixture",
            inputUSDPerMillionTokens: 1, outputUSDPerMillionTokens: 2
        )
        let resolved = EvaluationResolvedJudgeConnection(connection: connection, apiKey: nil)
        let client = EvaluationCompatibleJudgeClient()
        let check = try await client.checkConnection(resolved)
        #expect(check.modelFound)
        #expect(check.structuredOutputsVerified == true)
        #expect(check.multimodalVerified == false)

        var suite = EvaluationSuite()
        suite.criteria = "The answer is supported."
        suite.judgeConfiguration = .init(
            mode: .connection,
            connectionID: connection.id,
            externalEvidenceApprovedAt: Date(),
            includeReferenceAttachments: false,
            approvedConnectionID: connection.id,
            approvedIncludeReferenceAttachments: false,
            approvedConnectionDigest: connection.disclosureDigest
        )
        let result = try await client.judge(
            response: "Blue light is scattered.",
            evaluationCase: suite.cases[0],
            effectivePrompt: suite.cases[0].prompt,
            suite: suite,
            images: [],
            toolEvidence: "tool=lookup; outcome=success",
            resolved: resolved
        )
        #expect(result.judgment.score == 4)
        #expect(result.identity.reportedModelID == "judge-fixture-reported")
        #expect(result.identity.provider == "fixture-provider")
        #expect(result.usage?.inputTokens == 10)
        #expect(result.cost.availability == .estimated)
        #expect(result.cost.usd == 0.00002)
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedVerdictRetriesOnceThenFailsClosed() async throws {
        let fixture = try CompatibleJudgeFixture(mode: .malformed)
        defer { fixture.stop() }
        let connection = EvaluationJudgeConnection(
            id: UUID(), name: "Broken judge", kind: .localCompatible,
            baseURL: fixture.baseURL, modelID: "judge-fixture"
        )
        var suite = EvaluationSuite()
        suite.criteria = "The answer is supported."
        suite.judgeConfiguration = .init(
            mode: .connection, connectionID: connection.id,
            externalEvidenceApprovedAt: Date(), includeReferenceAttachments: false,
            approvedConnectionID: connection.id, approvedIncludeReferenceAttachments: false,
            approvedConnectionDigest: connection.disclosureDigest
        )
        do {
            _ = try await EvaluationCompatibleJudgeClient().judge(
                response: "Response", evaluationCase: suite.cases[0],
                effectivePrompt: suite.cases[0].prompt, suite: suite,
                images: [], toolEvidence: nil,
                resolved: .init(connection: connection, apiKey: nil)
            )
            Issue.record("Expected malformed judgment to fail closed.")
        } catch let error as EvaluationCompatibleJudgeError {
            #expect(error.localizedDescription.contains("after one bounded retry"))
        }
        #expect(fixture.completionRequestCount == 2)
    }

    @Test func disclosureAndMultimodalCapabilitiesAreMandatory() async throws {
        let connection = EvaluationJudgeConnection(
            id: UUID(), name: "Local", kind: .localCompatible,
            baseURL: "http://127.0.0.1:19999/v1", modelID: "judge"
        )
        var suite = EvaluationSuite()
        suite.criteria = "Requirement"
        suite.judgeConfiguration = .init(
            mode: .connection, connectionID: connection.id,
            externalEvidenceApprovedAt: nil, includeReferenceAttachments: true
        )
        await #expect(throws: EvaluationCompatibleJudgeError.self) {
            try await EvaluationCompatibleJudgeClient().judge(
                response: "R", evaluationCase: suite.cases[0], effectivePrompt: "P",
                suite: suite, images: [], toolEvidence: nil,
                resolved: .init(connection: connection, apiKey: nil)
            )
        }
        suite.judgeConfiguration.externalEvidenceApprovedAt = Date()
        suite.judgeConfiguration.approvedConnectionID = connection.id
        suite.judgeConfiguration.approvedIncludeReferenceAttachments = true
        suite.judgeConfiguration.approvedConnectionDigest = connection.disclosureDigest
        let image = ImageEvaluationInput(label: "image", url: URL(filePath: "/tmp/not-read.png"))
        await #expect(throws: EvaluationCompatibleJudgeError.self) {
            try await EvaluationCompatibleJudgeClient().judge(
                response: "R", evaluationCase: suite.cases[0], effectivePrompt: "P",
                suite: suite, images: [image], toolEvidence: nil,
                resolved: .init(connection: connection, apiKey: nil)
            )
        }
    }

    @Test func disclosureApprovalIsBoundToConnectionAndAttachmentSharing() {
        let connectionID = UUID()
        var configuration = EvaluationJudgeConfiguration(
            mode: .connection, connectionID: connectionID,
            externalEvidenceApprovedAt: Date(), includeReferenceAttachments: false,
            approvedConnectionID: connectionID, approvedIncludeReferenceAttachments: false,
            approvedConnectionDigest: nil
        )
        var connection = EvaluationJudgeConnection(
            id: connectionID, name: "Fixture", kind: .localCompatible,
            baseURL: "http://127.0.0.1:11434/v1", modelID: "judge"
        )
        configuration.approvedConnectionDigest = connection.disclosureDigest
        #expect(configuration.hasCurrentExternalEvidenceApproval(for: connection))

        configuration.connectionID = UUID()
        #expect(!configuration.hasCurrentExternalEvidenceApproval(for: connection))

        configuration.connectionID = connectionID
        configuration.includeReferenceAttachments = true
        #expect(!configuration.hasCurrentExternalEvidenceApproval(for: connection))

        configuration.includeReferenceAttachments = false
        connection.modelID = "different-judge"
        #expect(!configuration.hasCurrentExternalEvidenceApproval(for: connection))
    }
}

final class CompatibleJudgeFixture: @unchecked Sendable {
    enum Mode { case valid, malformed }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "FoundationEvalsTests.CompatibleJudgeFixture")
    private let ready = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let mode: Mode
    private var requestCount = 0
    private var completionRequests: [String] = []
    private(set) var port: UInt16 = 0

    var baseURL: String { "http://127.0.0.1:\(port)/v1" }
    var completionRequestCount: Int { lock.withLock { requestCount } }
    var lastCompletionRequest: String? { lock.withLock { completionRequests.last } }

    init(mode: Mode) throws {
        self.mode = mode
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.port = self.listener.port?.rawValue ?? 0
                self.ready.signal()
            case .failed:
                self.ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, port != 0 else {
            listener.cancel()
            throw FixtureError.listen
        }
    }

    func stop() { listener.cancel() }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, data: Data())
    }

    private func receive(_ connection: NWConnection, data accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1_024) { [weak self] data, _, complete, error in
            guard let self else { return }
            var request = accumulated
            if let data { request.append(data) }
            guard error == nil else { connection.cancel(); return }
            guard self.isCompleteHTTPRequest(request) else {
                if complete { connection.cancel() } else { self.receive(connection, data: request) }
                return
            }
            self.respond(to: request, connection: connection)
        }
    }

    private func respond(to request: Data, connection: NWConnection) {
        let first = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
        let body: Data
        if first.contains("/models") {
            body = Data(#"{"data":[{"id":"judge-fixture","supported_parameters":["response_format"],"architecture":{"input_modalities":["text"]}}]}"#.utf8)
        } else {
            lock.withLock {
                requestCount += 1
                completionRequests.append(String(decoding: request, as: UTF8.self))
            }
            let content = mode == .valid
                ? #"{"requirements":[{"criterionIndex":1,"score":4,"rationale":"Supported by the saved evidence."}]}"#
                : #"{"requirements":[]}"#
            body = try! JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": content]]],
                "model": "judge-fixture-reported",
                "provider": "fixture-provider",
                "usage": ["prompt_tokens": 10, "completion_tokens": 5]
            ], options: [.sortedKeys])
        }
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(head.utf8) + body,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    private func isCompleteHTTPRequest(_ request: Data) -> Bool {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = request.range(of: separator) else { return false }
        let header = String(decoding: request[..<headerRange.lowerBound], as: UTF8.self)
        let contentLength = header.components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) }
            ?? 0
        return request.count >= headerRange.upperBound + contentLength
    }

    private enum FixtureError: Error { case listen }
}
