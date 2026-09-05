import Foundation

actor MCPProtocolHandler {
    static let protocolVersion = "2025-06-18"

    private let port: Int
    private let authority: MCPAuthority
    private let onRequest: (@Sendable (Date) async -> Void)?
    private let maximumBodyBytes: Int
    private let maximumConcurrentRequests: Int
    private var activeAdmissions: Set<UUID> = []

    init(
        port: Int = 17_873,
        authority: MCPAuthority,
        maximumBodyBytes: Int = 16 * 1_024 * 1_024,
        maximumConcurrentRequests: Int = 8,
        onRequest: (@Sendable (Date) async -> Void)? = nil
    ) {
        precondition((1...65_535).contains(port))
        precondition(maximumBodyBytes > 0)
        precondition(maximumConcurrentRequests > 0)
        self.port = port
        self.authority = authority
        self.onRequest = onRequest
        self.maximumBodyBytes = maximumBodyBytes
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }

    func handle(_ request: MCPHTTPRequest) async -> MCPHTTPResponse {
        switch await preflight(request) {
        case .rejected(let response):
            return response
        case .admitted(let admission):
            return await handleAdmitted(request, admission: admission)
        }
    }

    func preflight(_ request: MCPHTTPRequest) async -> MCPRequestPreflight {
        if request.path != "/mcp" { return .empty(404) }
        guard request.method == "POST" else { return .empty(405, allow: "POST") }
        guard hostIsAllowed(request[header: "host"]), originIsAllowed(request[header: "origin"]) else {
            return .rejected(.empty(403))
        }
        guard isJSONContentType(request[header: "content-type"]) else {
            return .rejected(.empty(415))
        }
        guard activeAdmissions.count < maximumConcurrentRequests else {
            var response = MCPHTTPResponse.empty(503)
            response.headers["Retry-After"] = "1"
            return .rejected(response)
        }

        let admission = MCPRequestAdmission()
        activeAdmissions.insert(admission.id)
        await onRequest?(Date())
        return .admitted(admission)
    }

    func abandon(_ admission: MCPRequestAdmission) {
        activeAdmissions.remove(admission.id)
    }

    func handleAdmitted(
        _ request: MCPHTTPRequest,
        admission: MCPRequestAdmission
    ) async -> MCPHTTPResponse {
        guard activeAdmissions.contains(admission.id) else {
            return rpcError(id: .null, code: -32_603, message: "Internal error.")
        }
        defer { activeAdmissions.remove(admission.id) }
        guard request.body.count <= maximumBodyBytes else { return .empty(413) }
        return await process(request)
    }

    private func process(_ httpRequest: MCPHTTPRequest) async -> MCPHTTPResponse {
        do {
            _ = try JSONDecoder().decode(MCPJSONValue.self, from: httpRequest.body)
        } catch {
            return rpcError(status: 400, id: .null, code: -32_700, message: "Parse error.")
        }

        let request: MCPRPCRequest
        do {
            request = try JSONDecoder().decode(MCPRPCRequest.self, from: httpRequest.body)
        } catch {
            return rpcError(status: 400, id: .null, code: -32_600, message: "Invalid Request.")
        }

        guard request.jsonrpc == "2.0", request.validID,
              request.params == nil || request.params?.objectValue != nil
        else {
            return rpcError(status: 400, id: request.id ?? .null, code: -32_600, message: "Invalid Request.")
        }

        if request.method == "initialize" {
            guard request.stringParameter("protocolVersion") != nil else {
                return rpcError(
                    status: 400,
                    id: request.id ?? .null,
                    code: -32_602,
                    message: "Initialize protocolVersion is required."
                )
            }
        } else {
            let version = httpRequest[header: "mcp-protocol-version"] ?? ""
            guard version == Self.protocolVersion else {
                return unsupportedVersion(requested: version, id: request.id ?? .null)
            }
        }

        if request.id == nil {
            return .empty(202)
        }

        return await route(request)
    }

    private func route(_ request: MCPRPCRequest) async -> MCPHTTPResponse {
        switch request.method {
        case "initialize":
            return rpcResult(
                id: request.id!,
                value: .object([
                    "protocolVersion": .string(Self.protocolVersion),
                    "capabilities": capabilities,
                    "serverInfo": serverInfo,
                    "instructions": .string(Self.instructions)
                ])
            )
        case "ping":
            return rpcResult(id: request.id!, value: .object([:]))
        case "tools/list":
            guard request.parameter("cursor") == nil else {
                return rpcError(id: request.id!, code: -32_602, message: "Tool list cursor is invalid.")
            }
            guard let tools = try? MCPJSONValue.encode(MCPToolCatalog.definitions) else {
                return rpcError(id: request.id!, code: -32_603, message: "Internal error.")
            }
            return rpcResult(id: request.id!, value: .object(["tools": tools]))
        case "tools/call":
            return await callTool(request)
        case "resources/list":
            guard request.parameter("cursor") == nil else {
                return rpcError(id: request.id!, code: -32_602, message: "Resource list cursor is invalid.")
            }
            return rpcResult(id: request.id!, value: .object(["resources": .array([])]))
        case "resources/templates/list":
            guard request.parameter("cursor") == nil else {
                return rpcError(id: request.id!, code: -32_602, message: "Resource template cursor is invalid.")
            }
            return rpcResult(id: request.id!, value: .object([
                "resourceTemplates": .array(MCPToolCatalog.resourceTemplates)
            ]))
        case "resources/read":
            return await readResource(request)
        default:
            return rpcError(
                id: request.id!,
                code: -32_601,
                message: "Method not found."
            )
        }
    }

    private func callTool(_ request: MCPRPCRequest) async -> MCPHTTPResponse {
        guard let name = request.stringParameter("name") else {
            return rpcError(id: request.id!, code: -32_602, message: "Tool name is required.")
        }
        let arguments: MCPJSONValue
        if let supplied = request.parameter("arguments") {
            guard supplied.objectValue != nil else {
                return rpcError(id: request.id!, code: -32_602, message: "Tool arguments must be an object.")
            }
            arguments = supplied
        } else {
            arguments = .object([:])
        }
        let call: MCPToolCall
        do {
            call = try MCPToolCatalog.parse(name: name, arguments: arguments)
        } catch MCPToolInputError.unknownTool {
            return rpcError(id: request.id!, code: -32_602, message: "Unknown tool.")
        } catch MCPToolInputError.confirmationRequired {
            return rpcError(id: request.id!, code: -32_602, message: "Explicit confirmation is required.")
        } catch {
            return rpcError(id: request.id!, code: -32_602, message: "Invalid tool arguments.")
        }

        var payload = await authority.call(call)
        let text: String
        do {
            text = try payload.structuredContent.jsonText()
        } catch {
            payload = .failure(code: "invalid_authority_response", message: "The operation produced an invalid response.")
            text = (try? payload.structuredContent.jsonText()) ?? #"{"outcome":"failed"}"#
        }
        var result: [String: MCPJSONValue] = [
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "structuredContent": payload.structuredContent
        ]
        if payload.isError { result["isError"] = .bool(true) }
        return rpcResult(id: request.id!, value: .object(result))
    }

    private func readResource(_ request: MCPRPCRequest) async -> MCPHTTPResponse {
        guard let uri = request.stringParameter("uri"), let resource = MCPResourceRequest(uri: uri) else {
            return rpcError(id: request.id!, code: -32_602, message: "Resource URI is invalid or unavailable.")
        }
        let payload = await authority.readResource(resource)
        if payload.isError {
            return resourceError(payload, requestedURI: uri, id: request.id!)
        }
        guard payload.uri == uri, (payload.text == nil) != (payload.blob == nil) else {
            return rpcError(id: request.id!, code: -32_603, message: "Internal error.")
        }

        var content: [String: MCPJSONValue] = [
            "uri": .string(payload.uri),
            "mimeType": .string(payload.mimeType)
        ]
        if let text = payload.text {
            content["text"] = .string(text)
        } else if let blob = payload.blob {
            content["blob"] = .string(blob.base64EncodedString())
        }
        return rpcResult(id: request.id!, value: .object(["contents": .array([.object(content)])]))
    }

    private func resourceError(
        _ payload: MCPResourcePayload,
        requestedURI: String,
        id: MCPJSONValue
    ) -> MCPHTTPResponse {
        guard let text = payload.text,
              let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(MCPJSONValue.self, from: data),
              let error = value.objectValue?["error"]?.objectValue,
              let code = error["code"]?.stringValue
        else {
            return rpcError(id: id, code: -32_603, message: "Internal error.")
        }

        if code == "not_found" {
            return rpcError(
                id: id,
                code: -32_002,
                message: "Resource not found.",
                data: .object(["uri": .string(requestedURI)])
            )
        }
        return rpcError(id: id, code: -32_603, message: "Internal error.")
    }

    private func unsupportedVersion(requested: String, id: MCPJSONValue) -> MCPHTTPResponse {
        rpcError(
            status: 400,
            id: id,
            code: -32_022,
            message: "Unsupported protocol version.",
            data: .object([
                "requested": .string(requested),
                "supported": .array([.string(Self.protocolVersion)])
            ])
        )
    }

    private func rpcResult(id: MCPJSONValue, value: MCPJSONValue) -> MCPHTTPResponse {
        let result = value.objectValue ?? ["value": value]
        return jsonResponse(
            status: 200,
            value: .object(["jsonrpc": .string("2.0"), "id": id, "result": .object(result)])
        )
    }

    private func rpcError(
        status: Int = 200,
        id: MCPJSONValue,
        code: Int,
        message: String,
        data: MCPJSONValue? = nil
    ) -> MCPHTTPResponse {
        var error: [String: MCPJSONValue] = [
            "code": .integer(Int64(code)),
            "message": .string(message)
        ]
        if let data { error["data"] = data }
        return jsonResponse(
            status: status,
            value: .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(error)])
        )
    }

    private func jsonResponse(status: Int, value: MCPJSONValue) -> MCPHTTPResponse {
        var headers = MCPHTTPResponse.securityHeaders
        headers["Content-Type"] = "application/json; charset=utf-8"
        let body: Data
        do {
            body = try JSONEncoder.sorted.encode(value)
        } catch {
            body = Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error."}}"#.utf8)
        }
        return MCPHTTPResponse(status: status, headers: headers, body: body)
    }

    private func hostIsAllowed(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "127.0.0.1:\(port)" || host == "localhost:\(port)"
    }

    private func originIsAllowed(_ origin: String?) -> Bool {
        guard let origin, !origin.isEmpty else { return true }
        guard let components = URLComponents(string: origin),
              components.scheme?.lowercased() == "http",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty,
              components.port == port,
              let host = components.host?.lowercased()
        else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }

    private func isJSONContentType(_ header: String?) -> Bool {
        guard let header else { return false }
        let components = header.split(separator: ";", omittingEmptySubsequences: false)
        guard let mediaType = components.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              mediaType.caseInsensitiveCompare("application/json") == .orderedSame
        else { return false }

        return components.dropFirst().allSatisfy { component in
            let parameter = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = parameter.firstIndex(of: "=") else { return false }
            return !parameter[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !parameter[parameter.index(after: separator)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var serverInfo: MCPJSONValue {
        .object(["name": .string("foundation-evals"), "version": .string("1.0.0")])
    }

    private var capabilities: MCPJSONValue {
        .object([
            "tools": .object(["listChanged": .bool(false)]),
            "resources": .object(["subscribe": .bool(false), "listChanged": .bool(false)])
        ])
    }

    private static let instructions = "Manage the shared Foundation Evals suite, attachments, and on-device evaluation runs. Read eval_get_state before a mutation and reuse stable UUIDs after an uncertain response."
}

struct MCPRequestAdmission: Sendable {
    fileprivate let id = UUID()
}

enum MCPRequestPreflight: Sendable {
    case admitted(MCPRequestAdmission)
    case rejected(MCPHTTPResponse)

    static func empty(_ status: Int, allow: String? = nil) -> Self {
        .rejected(.empty(status, allow: allow))
    }
}

private struct MCPRPCRequest: Decodable {
    var jsonrpc: String
    var id: MCPJSONValue?
    var method: String
    var params: MCPJSONValue?

    var validID: Bool {
        guard let id else { return true }
        switch id {
        case .string, .integer, .unsigned: return true
        default: return false
        }
    }

    func stringParameter(_ name: String) -> String? {
        parameter(name)?.stringValue
    }

    func objectParameter(_ name: String) -> [String: MCPJSONValue]? {
        parameter(name)?.objectValue
    }

    func parameter(_ name: String) -> MCPJSONValue? {
        params?.objectValue?[name]
    }
}
