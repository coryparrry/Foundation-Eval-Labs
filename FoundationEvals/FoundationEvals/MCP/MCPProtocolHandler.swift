import Foundation

actor MCPProtocolHandler {
    static let modernVersion = "2026-07-28"
    static let legacyVersion = "2025-11-25"
    static let supportedVersions = [modernVersion, legacyVersion]

    private let port: Int
    private let bearerToken: String
    private let authority: MCPAuthority
    private let onAuthenticatedRequest: (@Sendable (Date) async -> Void)?
    private let maximumBodyBytes: Int
    private let maximumConcurrentRequests: Int
    private var activeAdmissions: Set<UUID> = []

    init(
        port: Int = 17_873,
        bearerToken: String,
        authority: MCPAuthority,
        maximumBodyBytes: Int = 16 * 1_024 * 1_024,
        maximumConcurrentRequests: Int = 8,
        onAuthenticatedRequest: (@Sendable (Date) async -> Void)? = nil
    ) {
        precondition((1...65_535).contains(port))
        precondition(!bearerToken.isEmpty)
        precondition(maximumBodyBytes > 0)
        precondition(maximumConcurrentRequests > 0)
        self.port = port
        self.bearerToken = bearerToken
        self.authority = authority
        self.onAuthenticatedRequest = onAuthenticatedRequest
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
        guard authenticated(request[header: "authorization"]) else {
            var response = MCPHTTPResponse.empty(401)
            response.headers["WWW-Authenticate"] = #"Bearer realm="Foundation Evals""#
            return .rejected(response)
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
        await onAuthenticatedRequest?(Date())
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

        let versionHeader = httpRequest[header: "mcp-protocol-version"]
        let inferredLegacyInitialize = versionHeader == nil && request.method == "initialize"
        let version = versionHeader ?? (inferredLegacyInitialize ? Self.legacyVersion : "")
        guard Self.supportedVersions.contains(version) else {
            return unsupportedVersion(requested: version, id: request.id ?? .null)
        }

        if version == Self.modernVersion {
            if let validationResponse = validateModernHeaders(httpRequest, request: request) {
                return validationResponse
            }
        } else if request.method == "initialize" {
            guard request.stringParameter("protocolVersion") == Self.legacyVersion else {
                return rpcError(
                    status: 400,
                    id: request.id ?? .null,
                    code: -32_602,
                    message: "Unsupported initialize protocolVersion."
                )
            }
        }

        if request.id == nil {
            return .empty(202)
        }

        return await route(request, version: version)
    }

    private func route(_ request: MCPRPCRequest, version: String) async -> MCPHTTPResponse {
        let modern = version == Self.modernVersion
        switch request.method {
        case "server/discover" where modern:
            return rpcResult(
                id: request.id!,
                value: .object([
                    "supportedVersions": .array(Self.supportedVersions.map(MCPJSONValue.string)),
                    "capabilities": capabilities(modern: true),
                    "serverInfo": serverInfo,
                    "instructions": .string(Self.instructions),
                    "ttlMs": .integer(300_000),
                    "cacheScope": .string("private")
                ]),
                modern: true
            )
        case "initialize" where !modern:
            return rpcResult(
                id: request.id!,
                value: .object([
                    "protocolVersion": .string(Self.legacyVersion),
                    "capabilities": capabilities(modern: false),
                    "serverInfo": serverInfo,
                    "instructions": .string(Self.instructions)
                ]),
                modern: false
            )
        case "ping":
            return rpcResult(id: request.id!, value: .object([:]), modern: modern)
        case "tools/list":
            guard request.parameter("cursor") == nil else {
                return rpcError(id: request.id!, code: -32_602, message: "Tool list cursor is invalid.")
            }
            guard let tools = try? MCPJSONValue.encode(MCPToolCatalog.definitions) else {
                return rpcError(id: request.id!, code: -32_603, message: "Internal error.")
            }
            var result: [String: MCPJSONValue] = [
                "tools": tools
            ]
            addCacheFields(to: &result, modern: modern, ttl: 300_000)
            return rpcResult(id: request.id!, value: .object(result), modern: modern)
        case "tools/call":
            return await callTool(request, modern: modern)
        case "resources/list":
            guard request.parameter("cursor") == nil else {
                return rpcError(id: request.id!, code: -32_602, message: "Resource list cursor is invalid.")
            }
            var result: [String: MCPJSONValue] = ["resources": .array([])]
            addCacheFields(to: &result, modern: modern, ttl: 0)
            return rpcResult(id: request.id!, value: .object(result), modern: modern)
        case "resources/templates/list":
            guard request.parameter("cursor") == nil else {
                return rpcError(id: request.id!, code: -32_602, message: "Resource template cursor is invalid.")
            }
            var result: [String: MCPJSONValue] = [
                "resourceTemplates": .array(MCPToolCatalog.resourceTemplates)
            ]
            addCacheFields(to: &result, modern: modern, ttl: 300_000)
            return rpcResult(id: request.id!, value: .object(result), modern: modern)
        case "resources/read":
            return await readResource(request, modern: modern)
        default:
            return rpcError(
                status: modern ? 404 : 200,
                id: request.id!,
                code: -32_601,
                message: "Method not found."
            )
        }
    }

    private func callTool(_ request: MCPRPCRequest, modern: Bool) async -> MCPHTTPResponse {
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
        return rpcResult(id: request.id!, value: .object(result), modern: modern)
    }

    private func readResource(_ request: MCPRPCRequest, modern: Bool) async -> MCPHTTPResponse {
        guard let uri = request.stringParameter("uri"), let resource = MCPResourceRequest(uri: uri) else {
            return rpcError(id: request.id!, code: -32_602, message: "Resource URI is invalid or unavailable.")
        }
        let payload = await authority.readResource(resource)
        guard !payload.isError, payload.uri == uri, (payload.text == nil) != (payload.blob == nil) else {
            return rpcError(id: request.id!, code: -32_602, message: "Resource URI is invalid or unavailable.")
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
        var result: [String: MCPJSONValue] = ["contents": .array([.object(content)])]
        addCacheFields(to: &result, modern: modern, ttl: 0)
        return rpcResult(id: request.id!, value: .object(result), modern: modern)
    }

    private func validateModernHeaders(_ httpRequest: MCPHTTPRequest, request: MCPRPCRequest) -> MCPHTTPResponse? {
        guard let meta = request.objectParameter("_meta"),
              let metadataVersion = meta["io.modelcontextprotocol/protocolVersion"]?.stringValue,
              meta["io.modelcontextprotocol/clientCapabilities"]?.objectValue != nil
        else {
            return rpcError(
                status: 400,
                id: request.id ?? .null,
                code: -32_602,
                message: "Required MCP request metadata is invalid."
            )
        }
        guard metadataVersion == httpRequest[header: "mcp-protocol-version"],
              httpRequest[header: "mcp-method"] == request.method
        else {
            return rpcError(
                status: 400,
                id: request.id ?? .null,
                code: -32_020,
                message: "Required MCP headers do not match the request body."
            )
        }

        let expectedName: String?
        switch request.method {
        case "tools/call": expectedName = request.stringParameter("name")
        case "resources/read": expectedName = request.stringParameter("uri")
        default: expectedName = nil
        }
        if let expectedName {
            guard let encodedName = httpRequest[header: "mcp-name"],
                  decodeHeaderValue(encodedName) == expectedName
            else {
                return rpcError(
                    status: 400,
                    id: request.id ?? .null,
                    code: -32_020,
                    message: "Required MCP headers do not match the request body."
                )
            }
        }
        return nil
    }

    private func unsupportedVersion(requested: String, id: MCPJSONValue) -> MCPHTTPResponse {
        rpcError(
            status: 400,
            id: id,
            code: -32_022,
            message: "Unsupported protocol version.",
            data: .object([
                "requested": .string(requested),
                "supported": .array(Self.supportedVersions.map(MCPJSONValue.string))
            ])
        )
    }

    private func rpcResult(id: MCPJSONValue, value: MCPJSONValue, modern: Bool) -> MCPHTTPResponse {
        var result = value.objectValue ?? ["value": value]
        if modern {
            result["resultType"] = .string("complete")
            result["_meta"] = .object(["io.modelcontextprotocol/serverInfo": serverInfo])
        }
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

    private func addCacheFields(to result: inout [String: MCPJSONValue], modern: Bool, ttl: Int) {
        guard modern else { return }
        result["ttlMs"] = .integer(Int64(ttl))
        result["cacheScope"] = .string("private")
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

    private func authenticated(_ authorization: String?) -> Bool {
        guard let authorization, authorization.hasPrefix("Bearer ") else { return false }
        let supplied = Array(authorization.dropFirst("Bearer ".count).utf8)
        let expected = Array(bearerToken.utf8)
        let count = max(supplied.count, expected.count)
        var difference = supplied.count ^ expected.count
        for index in 0..<count {
            difference |= Int(
                (index < supplied.count ? supplied[index] : 0)
                    ^ (index < expected.count ? expected[index] : 0)
            )
        }
        return difference == 0
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

    private func decodeHeaderValue(_ value: String) -> String? {
        if value.hasPrefix("=?base64?") && value.hasSuffix("?=") {
            let start = value.index(value.startIndex, offsetBy: "=?base64?".count)
            let end = value.index(value.endIndex, offsetBy: -2)
            guard let data = Data(base64Encoded: String(value[start..<end]), options: []) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) })
        else { return nil }
        return value
    }

    private var serverInfo: MCPJSONValue {
        .object(["name": .string("foundation-evals"), "version": .string("1.0.0")])
    }

    private func capabilities(modern: Bool) -> MCPJSONValue {
        .object([
            "tools": modern ? .object([:]) : .object(["listChanged": .bool(false)]),
            "resources": modern
                ? .object([:])
                : .object(["subscribe": .bool(false), "listChanged": .bool(false)])
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
