import Foundation

enum EvaluationCaseImportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case jsonLines

    var id: Self { self }
}

struct EvaluationCaseImportMapping: Equatable, Sendable {
    var nameColumn: String?
    var promptColumn: String
    var expectedColumn: String?
}

struct EvaluationCaseImportRow: Identifiable, Sendable {
    var id = UUID()
    var sourceLine: Int
    var name: String
    var prompt: String
    var expected: String
}

struct EvaluationCaseImportIssue: Identifiable, Equatable, Sendable {
    var id: String { "\(line ?? 0):\(message)" }
    var line: Int?
    var message: String
}

struct EvaluationCaseImportPreview: Sendable {
    var columns: [String]
    var rows: [EvaluationCaseImportRow]
    var issues: [EvaluationCaseImportIssue]

    var canImport: Bool { !rows.isEmpty && issues.isEmpty }
}

enum EvaluationCaseImporter {
    static func columns(in data: Data, format: EvaluationCaseImportFormat) throws -> [String] {
        try validateFileSize(data)
        switch format {
        case .csv:
            let rows = try csvRows(data)
            guard let header = rows.first else { throw EvaluationCaseImportError.emptyFile }
            return try validatedColumns(header.fields)
        case .jsonLines:
            let records = try jsonLineRecords(data)
            guard let first = records.first else { throw EvaluationCaseImportError.emptyFile }
            return first.object.keys.sorted()
        }
    }

    static func preview(
        data: Data,
        format: EvaluationCaseImportFormat,
        mapping: EvaluationCaseImportMapping,
        limit: Int = 20
    ) throws -> EvaluationCaseImportPreview {
        try validateFileSize(data)
        switch format {
        case .csv:
            return try csvPreview(data: data, mapping: mapping, limit: limit)
        case .jsonLines:
            return try jsonLinesPreview(data: data, mapping: mapping, limit: limit)
        }
    }

    static func cases(
        data: Data,
        format: EvaluationCaseImportFormat,
        mapping: EvaluationCaseImportMapping,
        maximumCases: Int
    ) throws -> [EvaluationCase] {
        let preview = try preview(data: data, format: format, mapping: mapping, limit: .max)
        guard preview.issues.isEmpty else { throw EvaluationCaseImportError.validation(preview.issues) }
        guard preview.rows.count <= maximumCases else {
            throw EvaluationCaseImportError.tooManyRows(maximum: maximumCases)
        }
        return preview.rows.map {
            EvaluationCase(name: $0.name, prompt: $0.prompt, expected: $0.expected)
        }
    }

    private static func csvPreview(
        data: Data,
        mapping: EvaluationCaseImportMapping,
        limit: Int
    ) throws -> EvaluationCaseImportPreview {
        let parsed = try csvRows(data)
        guard let header = parsed.first else { throw EvaluationCaseImportError.emptyFile }
        let columns = try validatedColumns(header.fields)
        try validate(mapping: mapping, columns: columns)
        var rows: [EvaluationCaseImportRow] = []
        var issues: [EvaluationCaseImportIssue] = []
        for row in parsed.dropFirst() {
            if row.fields.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            guard row.fields.count == columns.count else {
                issues.append(.init(line: row.line, message: "Expected \(columns.count) columns but found \(row.fields.count)."))
                continue
            }
            let object = Dictionary(uniqueKeysWithValues: zip(columns, row.fields))
            append(object: object, line: row.line, mapping: mapping, rows: &rows, issues: &issues, limit: limit)
        }
        return EvaluationCaseImportPreview(columns: columns, rows: rows, issues: issues)
    }

    private static func jsonLinesPreview(
        data: Data,
        mapping: EvaluationCaseImportMapping,
        limit: Int
    ) throws -> EvaluationCaseImportPreview {
        let records = try jsonLineRecords(data)
        let columns = records.reduce(into: Set<String>()) { $0.formUnion($1.object.keys) }.sorted()
        try validate(mapping: mapping, columns: columns)
        var rows: [EvaluationCaseImportRow] = []
        var issues: [EvaluationCaseImportIssue] = []
        for record in records {
            var object: [String: String] = [:]
            for (key, value) in record.object {
                if let value = value as? String {
                    object[key] = value
                } else if value is NSNull {
                    object[key] = ""
                } else {
                    issues.append(.init(line: record.line, message: "Column '\(key)' must be a string or null."))
                }
            }
            append(object: object, line: record.line, mapping: mapping, rows: &rows, issues: &issues, limit: limit)
        }
        return EvaluationCaseImportPreview(columns: columns, rows: rows, issues: issues)
    }

    private static func append(
        object: [String: String],
        line: Int,
        mapping: EvaluationCaseImportMapping,
        rows: inout [EvaluationCaseImportRow],
        issues: inout [EvaluationCaseImportIssue],
        limit: Int
    ) {
        let prompt = object[mapping.promptColumn]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !prompt.isEmpty else {
            issues.append(.init(line: line, message: "The mapped prompt value is empty."))
            return
        }
        guard prompt.count <= EvaluationStore.maximumFieldCharacters else {
            issues.append(.init(line: line, message: "The prompt exceeds \(EvaluationStore.maximumFieldCharacters) characters."))
            return
        }
        let importedName = mapping.nameColumn.flatMap { object[$0] }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = importedName.flatMap { $0.isEmpty ? nil : $0 } ?? "Imported case \(line)"
        let expected = mapping.expectedColumn.flatMap { object[$0] } ?? ""
        guard expected.count <= EvaluationStore.maximumFieldCharacters else {
            issues.append(.init(line: line, message: "The expected answer exceeds \(EvaluationStore.maximumFieldCharacters) characters."))
            return
        }
        if rows.count < limit {
            rows.append(.init(sourceLine: line, name: name, prompt: prompt, expected: expected))
        }
    }

    private static func validate(mapping: EvaluationCaseImportMapping, columns: [String]) throws {
        guard columns.contains(mapping.promptColumn) else {
            throw EvaluationCaseImportError.missingColumn(mapping.promptColumn)
        }
        if let name = mapping.nameColumn, !columns.contains(name) {
            throw EvaluationCaseImportError.missingColumn(name)
        }
        if let expected = mapping.expectedColumn, !columns.contains(expected) {
            throw EvaluationCaseImportError.missingColumn(expected)
        }
    }

    private static func validateFileSize(_ data: Data) throws {
        guard data.count <= EvaluationStore.maximumTextFileBytes else {
            throw EvaluationCaseImportError.fileTooLarge(maximumBytes: EvaluationStore.maximumTextFileBytes)
        }
    }

    private static func validatedColumns(_ columns: [String]) throws -> [String] {
        let trimmed = columns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trimmed.isEmpty, trimmed.allSatisfy({ !$0.isEmpty }) else {
            throw EvaluationCaseImportError.invalidHeader
        }
        guard Set(trimmed).count == trimmed.count else { throw EvaluationCaseImportError.duplicateColumns }
        return trimmed
    }

    private struct CSVRow {
        var line: Int
        var fields: [String]
    }

    private static func csvRows(_ data: Data) throws -> [CSVRow] {
        guard let text = String(data: data, encoding: .utf8) else { throw EvaluationCaseImportError.notUTF8 }
        var rows: [CSVRow] = []
        var fields: [String] = []
        var field = ""
        var quoted = false
        var line = 1
        var rowStart = 1
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = text.index(after: next)
                        continue
                    }
                    quoted = false
                } else {
                    field.append(character)
                    if character == "\n" { line += 1 }
                }
            } else {
                switch character {
                case "\"" where field.isEmpty:
                    quoted = true
                case ",":
                    fields.append(field)
                    field = ""
                case "\n":
                    fields.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
                    rows.append(CSVRow(line: rowStart, fields: fields))
                    fields = []
                    field = ""
                    line += 1
                    rowStart = line
                default:
                    field.append(character)
                }
            }
            index = next
        }
        guard !quoted else { throw EvaluationCaseImportError.unterminatedQuote(line: rowStart) }
        if !field.isEmpty || !fields.isEmpty {
            fields.append(field.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
            rows.append(CSVRow(line: rowStart, fields: fields))
        }
        return rows
    }

    private struct JSONLineRecord {
        var line: Int
        var object: [String: Any]
    }

    private static func jsonLineRecords(_ data: Data) throws -> [JSONLineRecord] {
        guard let text = String(data: data, encoding: .utf8) else { throw EvaluationCaseImportError.notUTF8 }
        return try text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { offset, raw in
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            guard let lineData = line.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                throw EvaluationCaseImportError.invalidJSONLine(line: offset + 1)
            }
            return JSONLineRecord(line: offset + 1, object: object)
        }
    }
}

enum EvaluationCaseImportError: LocalizedError, Sendable {
    case emptyFile
    case notUTF8
    case invalidHeader
    case duplicateColumns
    case unterminatedQuote(line: Int)
    case invalidJSONLine(line: Int)
    case missingColumn(String)
    case validation([EvaluationCaseImportIssue])
    case tooManyRows(maximum: Int)
    case fileTooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .emptyFile: "The import file has no records."
        case .notUTF8: "Case import files must use UTF-8 encoding."
        case .invalidHeader: "CSV headers must be non-empty."
        case .duplicateColumns: "CSV headers must be unique."
        case .unterminatedQuote(let line): "CSV line \(line) has an unterminated quoted field."
        case .invalidJSONLine(let line): "JSONL line \(line) is not a JSON object."
        case .missingColumn(let name): "The mapped column '\(name)' does not exist."
        case .validation(let issues): issues.first?.message ?? "The imported cases are invalid."
        case .tooManyRows(let maximum): "Import at most \(maximum) cases at a time."
        case .fileTooLarge(let maximumBytes): "Case import files must be \(maximumBytes) bytes or smaller."
        }
    }
}
