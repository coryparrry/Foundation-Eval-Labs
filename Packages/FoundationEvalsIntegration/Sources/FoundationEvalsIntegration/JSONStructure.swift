import Foundation

public enum JSONStructureError: Error, Equatable, LocalizedError {
    case truncated
    case invalidSyntax(String)
    case duplicateKey(String)
    case nestingTooDeep(maximum: Int)
    case notUTF8
    case trailingData

    public var errorDescription: String? {
        switch self {
        case .truncated: "The JSON ended before the value was complete."
        case .invalidSyntax(let detail): "The JSON is invalid: \(detail)."
        case .duplicateKey(let key): "Duplicate JSON key \"\(key)\" is not allowed."
        case .nestingTooDeep(let maximum): "JSON nesting exceeds the limit of \(maximum)."
        case .notUTF8: "JSON must be UTF-8."
        case .trailingData: "The JSON contains trailing data after the first value."
        }
    }
}

/// Validates nesting, strings, and duplicate keys without treating brackets inside strings as structure.
public enum JSONStructure {
    public static func validate(
        _ data: Data,
        maximumDepth: Int,
        rejectDuplicateKeys: Bool
    ) throws {
        var parser = Parser(data: data, maximumDepth: maximumDepth, rejectDuplicateKeys: rejectDuplicateKeys)
        try parser.parseValue()
        parser.skipWhitespace()
        if !parser.isAtEnd { throw JSONStructureError.trailingData }
    }

    public static func decodeJSON(_ data: Data, maximumDepth: Int = CaptureLimits.version1.maximumJSONNestingDepth) throws -> CaptureJSON {
        var parser = Parser(data: data, maximumDepth: maximumDepth, rejectDuplicateKeys: true)
        let value = try parser.parseJSONValue()
        parser.skipWhitespace()
        if !parser.isAtEnd { throw JSONStructureError.trailingData }
        return value
    }

    public static func captureJSON(from object: Any) throws -> CaptureJSON {
        switch object {
        case is NSNull:
            return .null
        case let value as Bool:
            return .bool(value)
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.stringValue)
        case let value as [Any]:
            return .array(try value.map { try captureJSON(from: $0) })
        case let value as [String: Any]:
            var object: [String: CaptureJSON] = [:]
            object.reserveCapacity(value.count)
            for (key, nested) in value {
                object[key] = try captureJSON(from: nested)
            }
            return .object(object)
        default:
            throw JSONStructureError.invalidSyntax("unsupported JSON value")
        }
    }
}

private struct Parser {
    let bytes: [UInt8]
    let maximumDepth: Int
    let rejectDuplicateKeys: Bool
    var index = 0

    init(data: Data, maximumDepth: Int, rejectDuplicateKeys: Bool) {
        self.bytes = [UInt8](data)
        self.maximumDepth = maximumDepth
        self.rejectDuplicateKeys = rejectDuplicateKeys
    }

    var isAtEnd: Bool { index >= bytes.count }

    mutating func parseValue(depth: Int = 1) throws {
        guard depth <= maximumDepth else { throw JSONStructureError.nestingTooDeep(maximum: maximumDepth) }
        skipWhitespace()
        guard let byte = peek() else { throw JSONStructureError.truncated }
        switch byte {
        case UInt8(ascii: "{"):
            try parseObject(depth: depth)
        case UInt8(ascii: "["):
            try parseArray(depth: depth)
        case UInt8(ascii: "\""):
            _ = try parseString()
        case UInt8(ascii: "t"):
            try parseLiteral("true")
        case UInt8(ascii: "f"):
            try parseLiteral("false")
        case UInt8(ascii: "n"):
            try parseLiteral("null")
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            _ = try parseNumberLiteral()
        default:
            throw JSONStructureError.invalidSyntax("unexpected byte")
        }
    }

    mutating func parseJSONValue(depth: Int = 1) throws -> CaptureJSON {
        guard depth <= maximumDepth else { throw JSONStructureError.nestingTooDeep(maximum: maximumDepth) }
        skipWhitespace()
        guard let byte = peek() else { throw JSONStructureError.truncated }
        switch byte {
        case UInt8(ascii: "{"):
            return try parseJSONObject(depth: depth)
        case UInt8(ascii: "["):
            return try parseJSONArray(depth: depth)
        case UInt8(ascii: "\""):
            return .string(try parseDecodedString())
        case UInt8(ascii: "t"):
            try parseLiteral("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try parseLiteral("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try parseLiteral("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return .number(try parseNumberLiteral())
        default:
            throw JSONStructureError.invalidSyntax("unexpected byte")
        }
    }

    mutating func parseJSONObject(depth: Int) throws -> CaptureJSON {
        try expect(UInt8(ascii: "{"))
        skipWhitespace()
        var object: [String: CaptureJSON] = [:]
        var keys: Set<String> = []
        if peek() == UInt8(ascii: "}") {
            index += 1
            return .object(object)
        }
        while true {
            skipWhitespace()
            let key = try parseDecodedString()
            if rejectDuplicateKeys, !keys.insert(key).inserted {
                throw JSONStructureError.duplicateKey(key)
            }
            skipWhitespace()
            try expect(UInt8(ascii: ":"))
            object[key] = try parseJSONValue(depth: depth + 1)
            skipWhitespace()
            if peek() == UInt8(ascii: "}") {
                index += 1
                return .object(object)
            }
            try expect(UInt8(ascii: ","))
        }
    }

    mutating func parseJSONArray(depth: Int) throws -> CaptureJSON {
        try expect(UInt8(ascii: "["))
        skipWhitespace()
        var values: [CaptureJSON] = []
        if peek() == UInt8(ascii: "]") {
            index += 1
            return .array(values)
        }
        while true {
            values.append(try parseJSONValue(depth: depth + 1))
            skipWhitespace()
            if peek() == UInt8(ascii: "]") {
                index += 1
                return .array(values)
            }
            try expect(UInt8(ascii: ","))
        }
    }

    mutating func parseDecodedString() throws -> String {
        let raw = try parseString()
        var quoted = Data([UInt8(ascii: "\"")])
        quoted.append(Data(raw.utf8))
        quoted.append(UInt8(ascii: "\""))
        guard let parsed = try JSONSerialization.jsonObject(with: quoted, options: [.fragmentsAllowed]) as? String else {
            throw JSONStructureError.invalidSyntax("invalid string")
        }
        return parsed
    }

    mutating func parseObject(depth: Int) throws {
        try expect(UInt8(ascii: "{"))
        skipWhitespace()
        var keys: Set<String> = []
        if peek() == UInt8(ascii: "}") {
            index += 1
            return
        }
        while true {
            skipWhitespace()
            let key = try parseString()
            if rejectDuplicateKeys, !keys.insert(key).inserted {
                throw JSONStructureError.duplicateKey(key)
            }
            skipWhitespace()
            try expect(UInt8(ascii: ":"))
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if peek() == UInt8(ascii: ",") {
                index += 1
                continue
            }
            try expect(UInt8(ascii: "}"))
            return
        }
    }

    mutating func parseArray(depth: Int) throws {
        try expect(UInt8(ascii: "["))
        skipWhitespace()
        if peek() == UInt8(ascii: "]") {
            index += 1
            return
        }
        while true {
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if peek() == UInt8(ascii: ",") {
                index += 1
                continue
            }
            try expect(UInt8(ascii: "]"))
            return
        }
    }

    mutating func parseString() throws -> String {
        try expect(UInt8(ascii: "\""))
        var scalars: [UInt8] = []
        while let byte = peek() {
            index += 1
            if byte == UInt8(ascii: "\"") {
                return String(decoding: scalars, as: UTF8.self)
            }
            if byte == UInt8(ascii: "\\") {
                guard let escaped = peek() else { throw JSONStructureError.truncated }
                index += 1
                scalars.append(UInt8(ascii: "\\"))
                scalars.append(escaped)
                if escaped == UInt8(ascii: "u") {
                    for _ in 0..<4 {
                        guard let hex = peek(), isHex(hex) else { throw JSONStructureError.invalidSyntax("invalid unicode escape") }
                        scalars.append(hex)
                        index += 1
                    }
                }
                continue
            }
            if byte < 0x20 { throw JSONStructureError.invalidSyntax("unescaped control character") }
            scalars.append(byte)
        }
        throw JSONStructureError.truncated
    }

    mutating func parseNumber() throws {
        _ = try parseNumberLiteral()
    }

    mutating func parseNumberLiteral() throws -> String {
        let start = index
        if peek() == UInt8(ascii: "-") { index += 1 }
        guard let first = peek(), isDigit(first) else { throw JSONStructureError.invalidSyntax("invalid number") }
        if first == UInt8(ascii: "0") {
            index += 1
        } else {
            while let byte = peek(), isDigit(byte) { index += 1 }
        }
        if peek() == UInt8(ascii: ".") {
            index += 1
            guard let byte = peek(), isDigit(byte) else { throw JSONStructureError.invalidSyntax("invalid fraction") }
            while let byte = peek(), isDigit(byte) { index += 1 }
        }
        if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
            index += 1
            if peek() == UInt8(ascii: "+") || peek() == UInt8(ascii: "-") { index += 1 }
            guard let byte = peek(), isDigit(byte) else { throw JSONStructureError.invalidSyntax("invalid exponent") }
            while let byte = peek(), isDigit(byte) { index += 1 }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    mutating func parseLiteral(_ expected: String) throws {
        for scalar in expected.utf8 {
            try expect(scalar)
        }
    }

    mutating func skipWhitespace() {
        while let byte = peek(), byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    func peek() -> UInt8? {
        guard index < bytes.count else { return nil }
        return bytes[index]
    }

    mutating func expect(_ byte: UInt8) throws {
        guard peek() == byte else { throw JSONStructureError.invalidSyntax("expected \(Character(UnicodeScalar(byte)))") }
        index += 1
    }

    func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }
    func isHex(_ byte: UInt8) -> Bool {
        isDigit(byte)
            || (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "f"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "F"))
    }
}
