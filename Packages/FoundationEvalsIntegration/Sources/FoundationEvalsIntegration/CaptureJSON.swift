import Foundation

/// JSON values that keep typed objects as JSON, not Swift descriptions or base64 `Data`.
public enum CaptureJSON: Sendable, Hashable {
    case object([String: CaptureJSON])
    case array([CaptureJSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

extension CaptureJSON: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([CaptureJSON].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: CaptureJSON].self) {
            self = .object(value)
        } else if let value = try? container.decode(Decimal.self) {
            self = .number(NSDecimalNumber(decimal: value).stringValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .number(let literal):
            let token = try CaptureJSONNumber.validated(literal)
            if let unsigned = UInt64(token), String(unsigned) == token {
                try container.encode(unsigned)
            } else if let signed = Int64(token), String(signed) == token {
                try container.encode(signed)
            } else if let decimal = Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")) {
                try container.encode(decimal)
            } else {
                throw EncodingError.invalidValue(
                    literal,
                    EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON number.")
                )
            }
        }
    }

    public static func fromEncoded<Value: Encodable>(_ value: Value) throws -> CaptureJSON {
        let data = try CaptureJSONCoding.encoder().encode(value)
        return try JSONStructure.decodeJSON(data)
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public func utf8Text(prettyPrinted: Bool = true) throws -> String {
        String(decoding: try CaptureJSONCoding.encoder(prettyPrinted: prettyPrinted).encode(self), as: UTF8.self)
    }
}

enum CaptureJSONNumber {
    static func validated(_ literal: String) throws -> String {
        let data = Data(literal.utf8)
        let parsed = try JSONStructure.decodeJSON(data, maximumDepth: 1)
        guard case .number(let token) = parsed, token == literal else {
            throw EncodingError.invalidValue(
                literal,
                EncodingError.Context(codingPath: [], debugDescription: "Invalid JSON number.")
            )
        }
        return token
    }
}

/// Distinguishes a missing output from a successful JSON `null`.
public enum CaptureOutput: Sendable, Equatable, Codable {
    case absent
    case returned(CaptureJSON)

    private enum CodingKeys: String, CodingKey {
        case kind, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "absent":
            self = .absent
        case "returned":
            self = .returned(try container.decode(CaptureJSON.self, forKey: .value))
        case let kind:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Unknown output kind \(kind)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .absent:
            try container.encode("absent", forKey: .kind)
        case .returned(let value):
            try container.encode("returned", forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}
