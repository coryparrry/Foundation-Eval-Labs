import Foundation
import Testing
@testable import FoundationEvals

struct MCPProtocolTests {
    private let token = "test-bearer-token"

    @Test func modernDiscoveryIncludesIdentityVersionsAndCacheContract() async throws {
        let handler = makeHandler()
        let response = await handler.handle(try modernRequest(method: "server/discover"))
        let json = try responseJSON(response)

        #expect(response.status == 200)
        #expect(json["result"]?["resultType"] == .string("complete"))
        #expect(json["result"]?["supportedVersions"] == .array([
            .string("2026-07-28"), .string("2025-11-25")
        ]))
        #expect(json["result"]?["ttlMs"] == .integer(300_000))
        #expect(json["result"]?["cacheScope"] == .string("private"))
        #expect(json["result"]?["serverInfo"]?["name"] == .string("foundation-evals"))
        #expect(json["result"]?["_meta"]?["io.modelcontextprotocol/serverInfo"]?["name"] == .string("foundation-evals"))
    }

    @Test func legacyInitializeUsesStableLifecycleShape() async throws {
        let handler = makeHandler()
        let response = await handler.handle(try legacyInitializeRequest())
        let result = try #require(responseJSON(response)["result"])

        #expect(response.status == 200)
        #expect(result["protocolVersion"] == .string("2025-11-25"))
        #expect(result["serverInfo"]?["name"] == .string("foundation-evals"))
        #expect(result["resultType"] == nil)
        #expect(result["ttlMs"] == nil)
    }

    @Test func modernMetadataErrorsAreDistinctFromHeaderMismatch() async throws {
        let handler = makeHandler()
        var missingMetadata = try modernRequest(method: "tools/list")
        missingMetadata.body = try rpcBody(id: 1, method: "tools/list", params: [:])
        let metadataResponse = await handler.handle(missingMetadata)

        var mismatchedHeader = try modernRequest(method: "tools/list")
        mismatchedHeader.headers["mcp-method"] = "resources/list"
        let mismatchResponse = await handler.handle(mismatchedHeader)

        #expect(metadataResponse.status == 400)
        #expect(try responseJSON(metadataResponse)["error"]?["code"] == .integer(-32_602))
        #expect(mismatchResponse.status == 400)
        #expect(try responseJSON(mismatchResponse)["error"]?["code"] == .integer(-32_020))
    }

    @Test func malformedJSONAndInvalidEnvelopeUseDistinctJSONRPCErrors() async throws {
        let handler = makeHandler()
        let malformed = await handler.handle(MCPHTTPRequest(
            method: "POST",
            headers: baseHeaders,
            body: Data(#"{"jsonrpc":"2.0""#.utf8)
        ))
        let invalidEnvelope = await handler.handle(MCPHTTPRequest(
            method: "POST",
            headers: baseHeaders,
            body: Data(#"{"jsonrpc":"2.0","id":1}"#.utf8)
        ))

        #expect(malformed.status == 400)
        #expect(try responseJSON(malformed)["error"]?["code"] == .integer(-32_700))
        #expect(invalidEnvelope.status == 400)
        #expect(try responseJSON(invalidEnvelope)["error"]?["code"] == .integer(-32_600))
    }

    @Test func jsonValuePreservesUnsignedIntegersBeyondInt64() throws {
        let original = MCPJSONValue.unsigned(UInt64.max)
        let encoded = try JSONEncoder.sorted.encode(original)
        let decoded = try JSONDecoder().decode(MCPJSONValue.self, from: encoded)

        #expect(decoded == original)
        #expect(String(decoding: encoded, as: UTF8.self) == "18446744073709551615")
    }

    @Test func suiteParserPreservesFullSeedAndEnforcesDomainControlBounds() throws {
        var configuration = MCPModelConfiguration(
            samplingMode: .probability,
            temperatureEnabled: true,
            temperature: 1,
            seedEnabled: true,
            seed: UInt64.max,
            topK: 1_000,
            probabilityThreshold: 0.01,
            maximumResponseTokens: 4_096,
            maximumInputTokens: 32_768,
            referenceMode: .inline,
            contextPolicy: .fitReferences,
            maximumToolCalls: 4
        )
        func arguments() throws -> MCPJSONValue {
            try MCPJSONValue.encode(MCPReplaceSuiteArguments(
                expectedRevision: "revision",
                confirmDeletes: false,
                suite: MCPSuiteDeclaration(
                    name: "",
                    version: "",
                    instructions: "",
                    scoringMode: .review,
                    repetitions: 1,
                    rubricRequirements: ["Useful"],
                    modelConfiguration: configuration,
                    cases: [MCPCaseDeclaration(id: UUID(), name: "", prompt: "Evaluate this.", expected: "")]
                )
            ))
        }

        let parsed = try MCPToolCatalog.parse(name: "eval_replace_suite", arguments: arguments())
        guard case .replaceSuite(let replacement) = parsed else {
            Issue.record("Expected a typed suite replacement.")
            return
        }
        #expect(replacement.suite.modelConfiguration.seed == UInt64.max)

        configuration.temperature = 1.01
        #expect(throws: MCPToolInputError.self) {
            try MCPToolCatalog.parse(name: "eval_replace_suite", arguments: arguments())
        }
    }

    @Test func securityAndTransportBoundsRejectBeforeDispatch() async throws {
        let recorder = MCPCallRecorder()
        let authority = MCPAuthority(
            call: { call in
                await recorder.record(call)
                return MCPToolPayload(structuredContent: .object(["outcome": .string("committed")]))
            },
            readResource: { _ in .failure(uri: "", code: "missing", message: "Missing") }
        )
        let handler = MCPProtocolHandler(
            bearerToken: token,
            authority: authority,
            maximumBodyBytes: 32
        )

        let methodResponse = await handler.handle(MCPHTTPRequest(method: "GET"))
        var hostRequest = try legacyInitializeRequest()
        hostRequest.headers["host"] = "example.com"
        let hostResponse = await handler.handle(hostRequest)
        var originRequest = try legacyInitializeRequest()
        originRequest.headers["origin"] = "https://example.com"
        let originResponse = await handler.handle(originRequest)
        var authenticationRequest = try legacyInitializeRequest()
        authenticationRequest.headers["authorization"] = "Bearer wrong"
        let authenticationResponse = await handler.handle(authenticationRequest)
        var oversizedRequest = try legacyInitializeRequest()
        oversizedRequest.body = Data(repeating: 0x41, count: 33)
        let oversizedResponse = await handler.handle(oversizedRequest)

        #expect(methodResponse.status == 405)
        #expect(methodResponse.headers["Allow"] == "POST")
        #expect(hostResponse.status == 403)
        #expect(originResponse.status == 403)
        #expect(authenticationResponse.status == 401)
        #expect(oversizedResponse.status == 413)
        #expect(await recorder.count == 0)
    }

    @Test func contentTypeRequiresJSONMediaTypeAndAllowsParameters() async throws {
        let handler = makeHandler()
        var invalid = try legacyInitializeRequest()
        invalid.headers["content-type"] = "application/jsonx"
        var parameterized = try legacyInitializeRequest()
        parameterized.headers["content-type"] = "application/json; charset=utf-8"

        let invalidResponse = await handler.handle(invalid)
        let parameterizedResponse = await handler.handle(parameterized)

        #expect(invalidResponse.status == 415)
        #expect(parameterizedResponse.status == 200)
    }

    @Test func admissionLimitRejectsExcessConcurrentRequests() async throws {
        let gate = MCPRequestGate()
        let authority = MCPAuthority(
            call: { _ in
                await gate.hold()
                return MCPToolPayload(structuredContent: .object(["outcome": .string("committed")]))
            },
            readResource: { _ in .failure(uri: "", code: "missing", message: "Missing") }
        )
        let handler = MCPProtocolHandler(
            bearerToken: token,
            authority: authority,
            maximumConcurrentRequests: 1
        )
        let request = try modernRequest(
            method: "tools/call",
            name: "eval_get_state",
            parameters: ["name": .string("eval_get_state"), "arguments": .object([:])]
        )

        let admitted = Task { await handler.handle(request) }
        await gate.waitUntilHeld()
        let rejected = await handler.handle(request)
        await gate.release()
        let completed = await admitted.value

        #expect(rejected.status == 503)
        #expect(rejected.headers["Retry-After"] == "1")
        #expect(completed.status == 200)
    }

    @Test func toolCatalogIsDeterministicTypedAndComplete() async throws {
        let handler = makeHandler()
        let first = await handler.handle(try modernRequest(method: "tools/list"))
        let second = await handler.handle(try modernRequest(method: "tools/list"))
        let tools = try #require(responseJSON(first)["result"]?["tools"]?.arrayValue)

        #expect(first.body == second.body)
        #expect(tools.count == 9)
        #expect(tools.compactMap { $0["name"]?.stringValue } == [
            "eval_get_state",
            "eval_replace_suite",
            "eval_upload_attachment",
            "eval_remove_attachment",
            "eval_start_run",
            "eval_get_run",
            "eval_list_runs",
            "eval_cancel_run",
            "eval_delete_run"
        ])
        #expect(tools.allSatisfy {
            $0["inputSchema"]?["$schema"] == .string("https://json-schema.org/draft/2020-12/schema")
        })
    }

    @Test func toolCallsAreTypedAndReturnStructuredAndTextContent() async throws {
        let recorder = MCPCallRecorder()
        let authority = MCPAuthority(
            call: { call in
                await recorder.record(call)
                return MCPToolPayload(structuredContent: .object([
                    "outcome": .string("committed"), "revision": .string("r2")
                ]))
            },
            readResource: { _ in .failure(uri: "", code: "missing", message: "Missing") }
        )
        let handler = MCPProtocolHandler(bearerToken: token, authority: authority)
        let response = await handler.handle(
            try modernRequest(
                method: "tools/call",
                name: "eval_get_state",
                parameters: ["name": .string("eval_get_state"), "arguments": .object([:])]
            )
        )
        let result = try #require(responseJSON(response)["result"])

        #expect(response.status == 200)
        #expect(result["structuredContent"]?["outcome"] == .string("committed"))
        #expect(result["content"]?.arrayValue?.first?["type"] == .string("text"))
        #expect(result["content"]?.arrayValue?.first?["text"]?.stringValue?.contains("committed") == true)
        #expect(await recorder.count == 1)
    }

    @Test func destructiveToolsRequireExplicitConfirmation() async throws {
        let recorder = MCPCallRecorder()
        let authority = MCPAuthority(
            call: { call in
                await recorder.record(call)
                return MCPToolPayload(structuredContent: .object([:]))
            },
            readResource: { _ in .failure(uri: "", code: "missing", message: "Missing") }
        )
        let handler = MCPProtocolHandler(bearerToken: token, authority: authority)
        let response = await handler.handle(
            try modernRequest(
                method: "tools/call",
                name: "eval_delete_run",
                parameters: [
                    "name": .string("eval_delete_run"),
                    "arguments": .object([
                        "runID": .string(UUID().uuidString),
                        "confirm": .bool(false)
                    ])
                ]
            )
        )

        #expect(response.status == 200)
        #expect(try responseJSON(response)["error"]?["code"] == .integer(-32_602))
        #expect(await recorder.count == 0)
    }

    @Test func resourceReadAcceptsEncodedRoutingNameAndOpaqueUUID() async throws {
        let id = UUID()
        let uri = "foundation-evals://runs/\(id.uuidString)"
        let authority = MCPAuthority(
            call: { _ in .failure(code: "unexpected", message: "Unexpected") },
            readResource: { request in
                #expect(request == .run(id))
                return .text(uri: uri, mimeType: "application/json", text: #"{"id":"run"}"#)
            }
        )
        let handler = MCPProtocolHandler(bearerToken: token, authority: authority)
        let encodedName = "=?base64?\(Data(uri.utf8).base64EncodedString())?="
        let response = await handler.handle(
            try modernRequest(
                method: "resources/read",
                name: encodedName,
                parameters: ["uri": .string(uri)]
            )
        )

        #expect(response.status == 200)
        #expect(try responseJSON(response)["result"]?["contents"]?.arrayValue?.first?["uri"] == .string(uri))
    }

    @Test func unsupportedProtocolAdvertisesBothImplementedVersions() async throws {
        var request = try modernRequest(method: "server/discover")
        request.headers["mcp-protocol-version"] = "2099-01-01"
        let response = await makeHandler().handle(request)
        let error = try #require(responseJSON(response)["error"])

        #expect(response.status == 400)
        #expect(error["code"] == .integer(-32_022))
        #expect(error["data"]?["supported"] == .array([
            .string("2026-07-28"), .string("2025-11-25")
        ]))
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil,
        "Requires loopback client access that the production app deliberately does not request."
    ))
    func hummingbirdServerBindsLoopbackAndSurfacesPortConflicts() async throws {
        let port = 27_873
        let gate = MCPRequestGate()
        let authority = MCPAuthority(
            call: { _ in
                await gate.hold()
                return MCPToolPayload(structuredContent: .object(["outcome": .string("committed")]))
            },
            readResource: { _ in .failure(uri: "", code: "missing", message: "Missing") }
        )
        let server = MCPServer(
            port: port,
            bearerToken: token,
            authority: authority,
            maximumConcurrentRequests: 1
        )
        try await server.start()

        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
            request.httpMethod = "POST"
            request.httpBody = try rpcBody(
                id: 1,
                method: "initialize",
                params: [
                    "protocolVersion": .string("2025-11-25"),
                    "capabilities": .object([:]),
                    "clientInfo": .object(["name": .string("test"), "version": .string("1")])
                ]
            )
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = try #require((response as? HTTPURLResponse)?.statusCode)
            guard status == 200 else {
                Issue.record("Expected HTTP 200, got \(status) with \(data.count) response bytes.")
                await server.stop()
                return
            }
            let json = try JSONDecoder().decode(MCPJSONValue.self, from: data)
            #expect(json["result"]?["protocolVersion"] == .string("2025-11-25"))

            var discovery = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
            discovery.httpMethod = "POST"
            discovery.httpBody = try rpcBody(
                id: 2,
                method: "server/discover",
                params: [
                    "_meta": .object([
                        "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
                        "io.modelcontextprotocol/clientCapabilities": .object([:]),
                        "io.modelcontextprotocol/clientInfo": .object([
                            "name": .string("FoundationEvalsTests"), "version": .string("1")
                        ])
                    ])
                ]
            )
            discovery.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            discovery.setValue("2026-07-28", forHTTPHeaderField: "MCP-Protocol-Version")
            discovery.setValue("server/discover", forHTTPHeaderField: "Mcp-Method")
            discovery.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (discoveryData, discoveryResponse) = try await URLSession.shared.data(for: discovery)
            #expect((discoveryResponse as? HTTPURLResponse)?.statusCode == 200)
            let discoveryJSON = try JSONDecoder().decode(MCPJSONValue.self, from: discoveryData)
            #expect(discoveryJSON["result"]?["resultType"] == .string("complete"))

            var hostile = request
            hostile.setValue("Bearer wrong", forHTTPHeaderField: "Authorization")
            let (_, hostileResponse) = try await URLSession.shared.data(for: hostile)
            #expect((hostileResponse as? HTTPURLResponse)?.statusCode == 401)

            var invalidMediaType = request
            invalidMediaType.setValue("application/jsonx", forHTTPHeaderField: "Content-Type")
            let (_, invalidMediaTypeResponse) = try await URLSession.shared.data(for: invalidMediaType)
            #expect((invalidMediaTypeResponse as? HTTPURLResponse)?.statusCode == 415)

            func toolCallRequest(id: Int) throws -> URLRequest {
                var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
                request.httpMethod = "POST"
                request.httpBody = try rpcBody(
                    id: id,
                    method: "tools/call",
                    params: [
                        "name": .string("eval_get_state"),
                        "arguments": .object([:]),
                        "_meta": .object([
                            "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
                            "io.modelcontextprotocol/clientCapabilities": .object([:])
                        ])
                    ]
                )
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("2026-07-28", forHTTPHeaderField: "MCP-Protocol-Version")
                request.setValue("tools/call", forHTTPHeaderField: "Mcp-Method")
                request.setValue("eval_get_state", forHTTPHeaderField: "Mcp-Name")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                return request
            }

            let admitted = Task { try await URLSession.shared.data(for: toolCallRequest(id: 3)) }
            await gate.waitUntilHeld()
            do {
                let (_, rejectedResponse) = try await URLSession.shared.data(for: toolCallRequest(id: 4))
                #expect((rejectedResponse as? HTTPURLResponse)?.statusCode == 503)
                await gate.release()
                let (_, completedResponse) = try await admitted.value
                #expect((completedResponse as? HTTPURLResponse)?.statusCode == 200)
            } catch {
                await gate.release()
                _ = try? await admitted.value
                throw error
            }

            let duplicate = MCPServer(port: port, bearerToken: token, authority: authority)
            do {
                try await duplicate.start()
                await duplicate.stop()
                Issue.record("Expected the occupied fixed port to fail.")
            } catch let error as MCPServerError {
                guard case .startFailed = error else {
                    Issue.record("Expected a port-conflict startup error, got \(error).")
                    await server.stop()
                    return
                }
            }
            await server.stop()

            let rebound = MCPServer(port: port, bearerToken: token, authority: authority)
            try await rebound.start()
            await rebound.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    private func makeHandler() -> MCPProtocolHandler {
        MCPProtocolHandler(
            bearerToken: token,
            authority: MCPAuthority(
                call: { _ in MCPToolPayload(structuredContent: .object(["outcome": .string("committed")])) },
                readResource: { _ in .failure(uri: "", code: "missing", message: "Missing") }
            )
        )
    }

    private func modernRequest(
        method: String,
        name: String? = nil,
        parameters: [String: MCPJSONValue] = [:]
    ) throws -> MCPHTTPRequest {
        var params = parameters
        params["_meta"] = .object([
            "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
            "io.modelcontextprotocol/clientCapabilities": .object([:]),
            "io.modelcontextprotocol/clientInfo": .object([
                "name": .string("FoundationEvalsTests"), "version": .string("1")
            ])
        ])
        var headers = baseHeaders
        headers["MCP-Protocol-Version"] = "2026-07-28"
        headers["Mcp-Method"] = method
        if let name { headers["Mcp-Name"] = name }
        return MCPHTTPRequest(
            method: "POST",
            headers: headers,
            body: try rpcBody(id: 1, method: method, params: params)
        )
    }

    private func legacyInitializeRequest() throws -> MCPHTTPRequest {
        MCPHTTPRequest(
            method: "POST",
            headers: baseHeaders.merging(["MCP-Protocol-Version": "2025-11-25"]) { _, new in new },
            body: try rpcBody(
                id: 1,
                method: "initialize",
                params: [
                    "protocolVersion": .string("2025-11-25"),
                    "capabilities": .object([:]),
                    "clientInfo": .object(["name": .string("test"), "version": .string("1")])
                ]
            )
        )
    }

    private var baseHeaders: [String: String] {
        [
            "Host": "127.0.0.1:17873",
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json"
        ]
    }

    private func rpcBody(id: Int, method: String, params: [String: MCPJSONValue]) throws -> Data {
        try JSONEncoder.sorted.encode(MCPJSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": .integer(Int64(id)),
            "method": .string(method),
            "params": .object(params)
        ]))
    }

    private func responseJSON(_ response: MCPHTTPResponse) throws -> MCPJSONValue {
        try JSONDecoder().decode(MCPJSONValue.self, from: #require(response.body))
    }
}

private actor MCPCallRecorder {
    private(set) var count = 0

    func record(_ call: MCPToolCall) {
        count += 1
    }
}

private actor MCPRequestGate {
    private var isHeld = false
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func hold() async {
        isHeld = true
        let waiters = heldWaiters
        heldWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilHeld() async {
        if isHeld { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private extension MCPJSONValue {
    subscript(_ key: String) -> MCPJSONValue? { objectValue?[key] }

    var arrayValue: [MCPJSONValue]? {
        guard case .array(let values) = self else { return nil }
        return values
    }
}
