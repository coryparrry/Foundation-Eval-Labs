import Foundation

enum MCPJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsigned(UInt64)
    case number(Double)
    case string(String)
    case array([MCPJSONValue])
    case object([String: MCPJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .unsigned(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: MCPJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .unsigned(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var objectValue: [String: MCPJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    static func encode<T: Encodable & Sendable>(_ value: T) throws -> MCPJSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(MCPJSONValue.self, from: data)
    }

    func decode<T: Decodable & Sendable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(type, from: data)
    }

    func jsonText() throws -> String {
        let data = try JSONEncoder.sorted.encode(self)
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPCodecError.invalidUTF8
        }
        return text
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

enum MCPCodecError: Error {
    case invalidUTF8
}

struct MCPHTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init(method: String, path: String = "/mcp", headers: [String: String] = [:], body: Data = Data()) {
        self.method = method.uppercased()
        self.path = path
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        self.body = body
    }

    subscript(header name: String) -> String? { headers[name.lowercased()] }
}

struct MCPHTTPResponse: Sendable {
    var status: Int
    var headers: [String: String]
    var body: Data?

    static func empty(_ status: Int, allow: String? = nil) -> Self {
        var headers = securityHeaders
        if let allow { headers["Allow"] = allow }
        return Self(status: status, headers: headers, body: nil)
    }

    static var securityHeaders: [String: String] {
        [
            "Cache-Control": "no-store",
            "Content-Security-Policy": "default-src 'none'",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff"
        ]
    }
}
