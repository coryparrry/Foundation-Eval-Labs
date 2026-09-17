import Foundation

public enum AppleEvaluationInspectionLabels {
    public static let plannedUnknown = "Planned coverage unknown"
    public static let metadataOnly = "Metadata-only · Per-sample rows were not converted"
    public static let ignoredCheck = "Check ignored · Not evidence of a pass"
    public static let originalFileOnly = "Some fields are available only in the original file"
    public static let crashRecoveryUnavailable = "Per-trial crash recovery is unavailable for this native export unless the producer recorded observations around each subject call."
}

public struct AppleEvaluationMetricInspection: Sendable, Equatable {
    public var name: String
    public var kind: String
    public var value: String?
    public var rationale: String?
    public var evaluatorKind: String?

    public init(
        name: String,
        kind: String,
        value: String? = nil,
        rationale: String? = nil,
        evaluatorKind: String? = nil
    ) {
        self.name = name
        self.kind = kind
        self.value = value
        self.rationale = rationale
        self.evaluatorKind = evaluatorKind
    }
}

public struct AppleEvaluationSampleInspection: Sendable, Equatable {
    public var index: Int
    public var fields: [String: String]
    public var subjectError: String?
    public var evaluatorError: String?
    public var metrics: [AppleEvaluationMetricInspection]

    public init(
        index: Int,
        fields: [String: String],
        subjectError: String?,
        evaluatorError: String?,
        metrics: [AppleEvaluationMetricInspection] = []
    ) {
        self.index = index
        self.fields = fields
        self.subjectError = subjectError
        self.evaluatorError = evaluatorError
        self.metrics = metrics
    }
}

public struct AppleEvaluationInspection: Sendable, Equatable {
    public var resultID: UUID
    public var evaluationID: String
    public var evaluationInfo: [String: String]
    public var startedAt: Date
    public var endedAt: Date
    public var inferenceFailureCount: Int
    public var evaluatorFailureCount: Int
    public var failingEvaluatorTypes: [String]
    public var metricsNotFound: [String]
    public var rowCount: Int
    public var columnNames: [String]
    public var samples: [AppleEvaluationSampleInspection]
    public var originalByteCount: Int
    public var digest: String
    public var warnings: [String]

    public init(
        resultID: UUID,
        evaluationID: String,
        evaluationInfo: [String: String],
        startedAt: Date,
        endedAt: Date,
        inferenceFailureCount: Int,
        evaluatorFailureCount: Int,
        failingEvaluatorTypes: [String],
        metricsNotFound: [String],
        rowCount: Int,
        columnNames: [String],
        samples: [AppleEvaluationSampleInspection],
        originalByteCount: Int,
        digest: String,
        warnings: [String]
    ) {
        self.resultID = resultID
        self.evaluationID = evaluationID
        self.evaluationInfo = evaluationInfo
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.inferenceFailureCount = inferenceFailureCount
        self.evaluatorFailureCount = evaluatorFailureCount
        self.failingEvaluatorTypes = failingEvaluatorTypes
        self.metricsNotFound = metricsNotFound
        self.rowCount = rowCount
        self.columnNames = columnNames
        self.samples = samples
        self.originalByteCount = originalByteCount
        self.digest = digest
        self.warnings = warnings
    }
}

public enum AppleEvaluationJSONError: Error, Equatable, LocalizedError {
    case notAnEvaluationResult

    public var errorDescription: String? {
        "The file is not an Apple evaluation result."
    }
}

/// Reads Apple's public saved-JSON representation (`results`, `runErrors`, identifiers).
/// This does not iterate native DataFrame columns.
public enum AppleEvaluationJSONInspector {
    private static let reserved = Set([
        "Input", "Response", "Expected", "SubjectInferenceError", "EvaluatorErrors", "Transcript",
    ])

    public static func inspect(bytes: Data) throws -> AppleEvaluationInspection {
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let resultIDString = root["resultID"] as? String,
              let resultID = UUID(uuidString: resultIDString),
              let evaluationID = root["evaluationID"] as? String
        else {
            throw AppleEvaluationJSONError.notAnEvaluationResult
        }

        let rows = root["results"] as? [[String: Any]] ?? []
        let samples = rows.enumerated().map(sample(index:row:))
        let ordering = ((root["reportMetadata"] as? [String: Any])?["ColumnOrdering"] as? [String]) ?? []
        let columnNames = ordering.isEmpty ? Array(Set(rows.flatMap(\.keys))).sorted() : ordering
        let errors = root["runErrors"] as? [String: Any] ?? [:]
        var warnings = [
            AppleEvaluationInspectionLabels.plannedUnknown,
            AppleEvaluationInspectionLabels.crashRecoveryUnavailable,
            AppleEvaluationInspectionLabels.originalFileOnly,
        ]
        if samples.contains(where: { sample in sample.metrics.contains { $0.kind == "ignore" } }) {
            warnings.append(AppleEvaluationInspectionLabels.ignoredCheck)
        }
        if samples.isEmpty {
            warnings.insert(AppleEvaluationInspectionLabels.metadataOnly, at: 0)
        }

        return AppleEvaluationInspection(
            resultID: resultID,
            evaluationID: evaluationID,
            evaluationInfo: stringMap(root["evaluationInfo"]),
            startedAt: date(root["startTime"]) ?? Date.distantPast,
            endedAt: date(root["endTime"]) ?? Date.distantPast,
            inferenceFailureCount: int(errors["inferenceFailureCount"]),
            evaluatorFailureCount: int(errors["evaluatorFailureCount"]),
            failingEvaluatorTypes: stringArray(errors["failingEvaluatorTypes"]).sorted(),
            metricsNotFound: stringArray(errors["metricsNotFound"]),
            rowCount: samples.count,
            columnNames: columnNames,
            samples: samples,
            originalByteCount: bytes.count,
            digest: CaptureDigest.sha256Hex(bytes),
            warnings: warnings
        )
    }

    private static func sample(index: Int, row: [String: Any]) -> AppleEvaluationSampleInspection {
        var fields: [String: String] = [:]
        if let input = display(row["Input"]) {
            fields["input"] = extractedPrompt(from: input) ?? input
        }
        if let response = responseText(row["Response"]) {
            fields["response"] = response
        }
        if let expected = display(row["Expected"]) {
            fields["expected"] = expected
        }
        var metrics: [AppleEvaluationMetricInspection] = []
        for (key, value) in row where !reserved.contains(key) {
            if let metric = metric(name: key, value: value) {
                metrics.append(metric)
            } else if let text = display(value) {
                fields[key] = text
            }
        }
        return AppleEvaluationSampleInspection(
            index: index,
            fields: fields,
            subjectError: display(row["SubjectInferenceError"]),
            evaluatorError: evaluatorError(row["EvaluatorErrors"]),
            metrics: metrics.sorted { $0.name < $1.name }
        )
    }

    private static func metric(name: String, value: Any) -> AppleEvaluationMetricInspection? {
        guard let object = value as? [String: Any], let kind = object["kind"] as? String else {
            return nil
        }
        return AppleEvaluationMetricInspection(
            name: name,
            kind: kind,
            value: display(object["value"]),
            rationale: object["rationale"] as? String,
            evaluatorKind: object["evaluatorKind"] as? String
        )
    }

    private static func responseText(_ value: Any?) -> String? {
        if value is NSNull || value == nil { return nil }
        if let object = value as? [String: Any], let inner = object["value"] {
            return display(inner)
        }
        return display(value)
    }

    private static func extractedPrompt(from text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let prompt = nestedPrompt(object) { return prompt }
        return nil
    }

    private static func nestedPrompt(_ object: [String: Any]) -> String? {
        if let prompt = object["prompt"] as? String { return prompt }
        if let input = object["input"] as? [String: Any], let prompt = nestedPrompt(input) {
            return prompt
        }
        return nil
    }

    private static func evaluatorError(_ value: Any?) -> String? {
        if let text = value as? String, !text.isEmpty { return text }
        if let values = value as? [Any] {
            let joined = values.compactMap(display).joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return display(value)
    }

    private static func display(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }

    private static func stringMap(_ value: Any?) -> [String: String] {
        guard let object = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, item) in object {
            if let text = display(item) { result[key] = text }
        }
        return result
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap(display)
    }

    private static func int(_ value: Any?) -> Int {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: text)
    }
}
