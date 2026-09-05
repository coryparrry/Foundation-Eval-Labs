import Foundation

/// The complete domain boundary required by the MCP transport.
///
/// Integration supplies one handler for every `MCPToolCall` and one handler for
/// `attachment` and `run` resource reads. Mutation handlers return an outcome of
/// `committed`, `duplicate`, `conflicted`, or `failed` in `structuredContent`;
/// the transport owns protocol validation and never reaches into the store.
struct MCPAuthority: Sendable {
    let call: @Sendable (MCPToolCall) async -> MCPToolPayload
    let readResource: @Sendable (MCPResourceRequest) async -> MCPResourcePayload

    init(
        call: @escaping @Sendable (MCPToolCall) async -> MCPToolPayload,
        readResource: @escaping @Sendable (MCPResourceRequest) async -> MCPResourcePayload
    ) {
        self.call = call
        self.readResource = readResource
    }
}

struct MCPToolPayload: Sendable {
    var structuredContent: MCPJSONValue
    var isError: Bool

    init(structuredContent: MCPJSONValue, isError: Bool = false) {
        self.structuredContent = structuredContent
        self.isError = isError
    }

    static func failure(code: String, message: String) -> Self {
        Self(
            structuredContent: .object([
                "outcome": .string("failed"),
                "error": .object(["code": .string(code), "message": .string(message)])
            ]),
            isError: true
        )
    }
}

enum MCPResourceRequest: Equatable, Sendable {
    case attachment(UUID)
    case run(UUID)

    init?(uri: String) {
        let mappings: [(String, (UUID) -> Self)] = [
            ("foundation-evals://attachments/", Self.attachment),
            ("foundation-evals://runs/", Self.run)
        ]
        for (prefix, make) in mappings where uri.hasPrefix(prefix) {
            let suffix = String(uri.dropFirst(prefix.count))
            guard !suffix.contains("/"), !suffix.contains("?"), !suffix.contains("#"), let id = UUID(uuidString: suffix) else {
                return nil
            }
            self = make(id)
            return
        }
        return nil
    }
}

struct MCPResourcePayload: Sendable {
    var uri: String
    var mimeType: String
    var text: String?
    var blob: Data?
    var isError: Bool

    static func text(uri: String, mimeType: String, text: String) -> Self {
        Self(uri: uri, mimeType: mimeType, text: text, blob: nil, isError: false)
    }

    static func blob(uri: String, mimeType: String, data: Data) -> Self {
        Self(uri: uri, mimeType: mimeType, text: nil, blob: data, isError: false)
    }

    static func failure(uri: String, code: String, message: String) -> Self {
        let value = MCPJSONValue.object([
            "outcome": .string("failed"),
            "error": .object(["code": .string(code), "message": .string(message)])
        ])
        return Self(
            uri: uri,
            mimeType: "application/json",
            text: (try? value.jsonText()) ?? #"{"outcome":"failed"}"#,
            blob: nil,
            isError: true
        )
    }
}

enum MCPToolCall: Sendable {
    case getState
    case replaceSuite(MCPReplaceSuiteArguments)
    case uploadAttachment(MCPUploadAttachmentArguments)
    case removeAttachment(MCPRemoveAttachmentArguments)
    case startRun(MCPStartRunArguments)
    case getRun(MCPGetRunArguments)
    case listRuns(MCPListRunsArguments)
    case analyzeRun(MCPAnalyzeRunArguments)
    case cancelRun(MCPCancelRunArguments)
    case deleteRun(MCPDeleteRunArguments)
}

struct MCPReplaceSuiteArguments: Codable, Sendable {
    var expectedRevision: String
    var confirmDeletes: Bool?
    var suite: MCPSuiteDeclaration
}

struct MCPSuiteDeclaration: Codable, Sendable {
    var name: String
    var version: String
    var instructions: String
    var scoringMode: MCPScoringMode
    var repetitions: Int
    var rubricRequirements: [String]
    var modelConfiguration: MCPModelConfiguration
    var cases: [MCPCaseDeclaration]
}

struct MCPCaseDeclaration: Codable, Sendable {
    var id: UUID
    var name: String
    var prompt: String
    var expected: String
}

enum MCPScoringMode: String, Codable, CaseIterable, Sendable {
    case review, exactMatch, containsExpected, modelJudge
}

enum MCPSamplingMode: String, Codable, CaseIterable, Sendable {
    case automatic, greedy, topK, probability
}

enum MCPReferenceMode: String, Codable, CaseIterable, Sendable {
    case inline, lookupTool
}

enum MCPContextPolicy: String, Codable, CaseIterable, Sendable {
    case fitReferences, requireFullInput
}

struct MCPModelConfiguration: Codable, Sendable {
    var samplingMode: MCPSamplingMode
    var temperatureEnabled: Bool
    var temperature: Double
    var seedEnabled: Bool
    var seed: UInt64
    var topK: Int
    var probabilityThreshold: Double
    var maximumResponseTokens: Int
    var maximumInputTokens: Int?
    var referenceMode: MCPReferenceMode
    var contextPolicy: MCPContextPolicy
    var maximumToolCalls: Int
}

struct MCPUploadAttachmentArguments: Codable, Sendable {
    var id: UUID
    var name: String
    var mediaType: String
    var dataBase64: Data
    var expectedRevision: String
}

struct MCPRemoveAttachmentArguments: Codable, Sendable {
    var id: UUID
    var expectedRevision: String
    var confirm: Bool
}

struct MCPStartRunArguments: Codable, Sendable {
    var runID: UUID
    var expectedRevision: String
}

struct MCPGetRunArguments: Codable, Sendable {
    var runID: UUID
    var cursor: String?
    var limit: Int?
}

struct MCPAnalyzeRunArguments: Codable, Sendable {
    var runID: UUID
    var baselineRunID: UUID?
}

struct MCPListRunsArguments: Codable, Sendable {
    var cursor: String?
    var limit: Int?
    var query: String?
    var status: String?
}

struct MCPCancelRunArguments: Codable, Sendable {
    var runID: UUID
}

struct MCPDeleteRunArguments: Codable, Sendable {
    var runID: UUID
    var confirm: Bool
}

struct MCPToolDefinition: Codable, Sendable {
    struct Annotations: Codable, Sendable {
        var readOnlyHint: Bool
        var destructiveHint: Bool
        var idempotentHint: Bool
        var openWorldHint = false
    }

    var name: String
    var title: String
    var description: String
    var inputSchema: MCPJSONValue
    var annotations: Annotations
}

enum MCPToolCatalog {
    static let definitions: [MCPToolDefinition] = [
        tool(
            "eval_get_state", "Get evaluation state",
            "Read the shared suite, revision, readiness, limits, capabilities, attachments, and active run.",
            properties: [:], required: [], readOnly: true
        ),
        tool(
            "eval_replace_suite", "Replace evaluation suite",
            "Atomically replace all editable suite fields and ordered cases while preserving suite identity and attachments.",
            properties: [
                "expectedRevision": string("Revision returned by eval_get_state."),
                "confirmDeletes": boolean("Must be true when existing cases are omitted."),
                "suite": suiteSchema
            ], required: ["expectedRevision", "suite"], idempotent: true
        ),
        tool(
            "eval_upload_attachment", "Upload attachment",
            "Upload one bounded text, PDF, or image attachment. Filesystem paths are never accepted.",
            properties: [
                "id": uuid("Stable caller-supplied attachment UUID."),
                "name": string("Display filename."),
                "mediaType": string("Declared MIME type."),
                "dataBase64": string("Base64-encoded file bytes.", contentEncoding: "base64"),
                "expectedRevision": string("Revision returned by eval_get_state.")
            ], required: ["id", "name", "mediaType", "dataBase64", "expectedRevision"], idempotent: true
        ),
        tool(
            "eval_remove_attachment", "Remove attachment",
            "Remove a suite attachment by its opaque UUID.",
            properties: [
                "id": uuid("Attachment UUID."),
                "expectedRevision": string("Revision returned by eval_get_state."),
                "confirm": boolean("Must be true.")
            ], required: ["id", "expectedRevision", "confirm"], destructive: true, idempotent: true
        ),
        tool(
            "eval_start_run", "Start evaluation run",
            "Validate the shared suite and start one durable asynchronous run. Reuse the same run UUID after an uncertain response.",
            properties: [
                "runID": uuid("Stable caller-supplied run UUID."),
                "expectedRevision": string("Exact suite revision to execute.")
            ], required: ["runID", "expectedRevision"], idempotent: true
        ),
        tool(
            "eval_get_run", "Get evaluation run",
            "Read active progress or paginated terminal results, traces, and errors.",
            properties: [
                "runID": uuid("Run UUID."),
                "cursor": string("Opaque cursor returned by this tool."),
                "limit": integer("Maximum results to return.", minimum: 1, maximum: 50)
            ], required: ["runID"], readOnly: true
        ),
        tool(
            "eval_list_runs", "List evaluation runs",
            "List cursor-paginated run summaries with optional text and status filters.",
            properties: [
                "cursor": string("Opaque cursor returned by this tool."),
                "limit": integer("Maximum summaries to return.", minimum: 1, maximum: 50),
                "query": string("Optional suite-name or version search."),
                "status": string("Optional run status filter.")
            ], required: [], readOnly: true
        ),
        tool(
            "eval_analyze_run", "Analyze evaluation run",
            "Summarize a saved run's coverage, per-case repeatability, latency and subject/judge token usage. Optionally compare a saved baseline, reporting incompatible cases and incomplete evidence explicitly. Does not run the model.",
            properties: [
                "runID": uuid("Saved candidate run UUID."),
                "baselineRunID": uuid("Optional saved baseline run UUID.")
            ], required: ["runID"], readOnly: true
        ),
        tool(
            "eval_cancel_run", "Cancel evaluation run",
            "Request cooperative cancellation of the identified active run; poll eval_get_run for its terminal state.",
            properties: ["runID": uuid("Run UUID.")], required: ["runID"], idempotent: true
        ),
        tool(
            "eval_delete_run", "Delete evaluation run",
            "Permanently delete a terminal run and its persisted trace.",
            properties: [
                "runID": uuid("Run UUID."),
                "confirm": boolean("Must be true.")
            ], required: ["runID", "confirm"], destructive: true, idempotent: true
        )
    ]

    static let resourceTemplates: [MCPJSONValue] = [
        .object([
            "name": .string("evaluation_attachment"),
            "title": .string("Evaluation attachment"),
            "uriTemplate": .string("foundation-evals://attachments/{attachmentID}"),
            "description": .string("Bounded extracted text or image bytes for a suite attachment.")
        ]),
        .object([
            "name": .string("evaluation_run"),
            "title": .string("Evaluation run export"),
            "uriTemplate": .string("foundation-evals://runs/{runID}"),
            "description": .string("Canonical complete JSON export for a persisted evaluation run."),
            "mimeType": .string("application/json")
        ])
    ]

    static func parse(name: String, arguments: MCPJSONValue) throws -> MCPToolCall {
        guard let definition = definitions.first(where: { $0.name == name }) else {
            throw MCPToolInputError.unknownTool
        }
        do {
            try rejectUndeclaredProperties(in: arguments, schema: definition.inputSchema)
            switch name {
            case "eval_get_state":
                let object = try requireObject(arguments)
                guard object.isEmpty else { throw MCPToolInputError.invalidArguments }
                return .getState
            case "eval_replace_suite":
                let value = try arguments.decode(MCPReplaceSuiteArguments.self)
                try validate(value)
                return .replaceSuite(value)
            case "eval_upload_attachment":
                let value = try arguments.decode(MCPUploadAttachmentArguments.self)
                guard !value.name.isEmpty, !value.mediaType.isEmpty, !value.expectedRevision.isEmpty else {
                    throw MCPToolInputError.invalidArguments
                }
                return .uploadAttachment(value)
            case "eval_remove_attachment":
                let value = try arguments.decode(MCPRemoveAttachmentArguments.self)
                guard value.confirm, !value.expectedRevision.isEmpty else { throw MCPToolInputError.confirmationRequired }
                return .removeAttachment(value)
            case "eval_start_run":
                let value = try arguments.decode(MCPStartRunArguments.self)
                guard !value.expectedRevision.isEmpty else { throw MCPToolInputError.invalidArguments }
                return .startRun(value)
            case "eval_get_run":
                let value = try arguments.decode(MCPGetRunArguments.self)
                try validatePage(cursor: value.cursor, limit: value.limit)
                return .getRun(value)
            case "eval_list_runs":
                let value = try arguments.decode(MCPListRunsArguments.self)
                try validatePage(cursor: value.cursor, limit: value.limit)
                guard (value.query?.count ?? 0) <= 1_024, (value.status?.count ?? 0) <= 64 else {
                    throw MCPToolInputError.invalidArguments
                }
                return .listRuns(value)
            case "eval_analyze_run":
                return .analyzeRun(try arguments.decode(MCPAnalyzeRunArguments.self))
            case "eval_cancel_run":
                return .cancelRun(try arguments.decode(MCPCancelRunArguments.self))
            case "eval_delete_run":
                let value = try arguments.decode(MCPDeleteRunArguments.self)
                guard value.confirm else { throw MCPToolInputError.confirmationRequired }
                return .deleteRun(value)
            default:
                throw MCPToolInputError.unknownTool
            }
        } catch let error as MCPToolInputError {
            throw error
        } catch {
            throw MCPToolInputError.invalidArguments
        }
    }

    private static func validate(_ arguments: MCPReplaceSuiteArguments) throws {
        let suite = arguments.suite
        guard !arguments.expectedRevision.isEmpty,
              (1...5).contains(suite.repetitions),
              (1...100).contains(suite.cases.count),
              suite.cases.count * suite.repetitions <= 100,
              (1...4).contains(suite.rubricRequirements.count),
              suite.instructions.count <= 32_000,
              suite.rubricRequirements.allSatisfy({ !$0.isEmpty && $0.count <= 4_000 }),
              suite.cases.allSatisfy({
                  !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.prompt.count <= 32_000
                      && $0.expected.count <= 32_000
              }),
              !suite.scoringMode.requiresExpected
                  || suite.cases.allSatisfy({ !$0.expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(suite.cases.map(\MCPCaseDeclaration.id)).count == suite.cases.count,
              suite.name.count + suite.version.count + suite.instructions.count
                + suite.rubricRequirements.reduce(0, { $0 + $1.count })
                + suite.cases.reduce(0, { $0 + $1.name.count + $1.prompt.count + $1.expected.count }) <= 256_000,
              suite.modelConfiguration.temperature.isFinite,
              (0...1).contains(suite.modelConfiguration.temperature),
              (1...1_000).contains(suite.modelConfiguration.topK),
              (0.01...1).contains(suite.modelConfiguration.probabilityThreshold),
              (128...4_096).contains(suite.modelConfiguration.maximumResponseTokens),
              suite.modelConfiguration.maximumInputTokens.map({ (512...32_768).contains($0) }) ?? true,
              (1...4).contains(suite.modelConfiguration.maximumToolCalls)
        else { throw MCPToolInputError.invalidArguments }
    }

    private static func validatePage(cursor: String?, limit: Int?) throws {
        guard (cursor?.count ?? 0) <= 512, (1...50).contains(limit ?? 50) else {
            throw MCPToolInputError.invalidArguments
        }
    }

    private static func requireObject(_ value: MCPJSONValue) throws -> [String: MCPJSONValue] {
        guard let object = value.objectValue else { throw MCPToolInputError.invalidArguments }
        return object
    }

    private static func rejectUndeclaredProperties(
        in value: MCPJSONValue,
        schema: MCPJSONValue
    ) throws {
        guard let schema = schema.objectValue else { return }

        if schema["type"]?.stringValue == "object",
           let object = value.objectValue,
           let properties = schema["properties"]?.objectValue {
            guard object.keys.allSatisfy({ properties[$0] != nil }) else {
                throw MCPToolInputError.invalidArguments
            }
            for (name, propertyValue) in object {
                if let propertySchema = properties[name] {
                    try rejectUndeclaredProperties(in: propertyValue, schema: propertySchema)
                }
            }
        } else if schema["type"]?.stringValue == "array",
                  case .array(let values) = value,
                  let itemSchema = schema["items"] {
            for item in values {
                try rejectUndeclaredProperties(in: item, schema: itemSchema)
            }
        }
    }

    private static func tool(
        _ name: String,
        _ title: String,
        _ description: String,
        properties: [String: MCPJSONValue],
        required: [String],
        readOnly: Bool = false,
        destructive: Bool = false,
        idempotent: Bool = false
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: name,
            title: title,
            description: description,
            inputSchema: object(properties: properties, required: required),
            annotations: .init(
                readOnlyHint: readOnly,
                destructiveHint: destructive,
                idempotentHint: idempotent
            )
        )
    }

    private static let suiteSchema = object(
        properties: [
            "name": string("Suite name."),
            "version": string("User-visible suite version."),
            "instructions": string("Instructions shared by every case.", maximumLength: 32_000),
            "scoringMode": string(enum: MCPScoringMode.allRawValues),
            "repetitions": integer("Samples per case.", minimum: 1, maximum: 5),
            "rubricRequirements": array(items: string(maximumLength: 4_000), minimum: 1, maximum: 4),
            "modelConfiguration": object(
                properties: [
                    "samplingMode": string(enum: MCPSamplingMode.allRawValues),
                    "temperatureEnabled": boolean(),
                    "temperature": number(minimum: 0, maximum: 1),
                    "seedEnabled": boolean(),
                    "seed": integer("Unsigned sampling seed.", minimum: 0),
                    "topK": integer(minimum: 1, maximum: 1_000),
                    "probabilityThreshold": number(minimum: 0.01, maximum: 1),
                    "maximumResponseTokens": integer(minimum: 128, maximum: 4_096),
                    "maximumInputTokens": nullableInteger(minimum: 512, maximum: 32_768),
                    "referenceMode": string(enum: MCPReferenceMode.allRawValues),
                    "contextPolicy": string(enum: MCPContextPolicy.allRawValues),
                    "maximumToolCalls": integer(minimum: 1, maximum: 4)
                ],
                required: [
                    "samplingMode", "temperatureEnabled", "temperature", "seedEnabled", "seed", "topK",
                    "probabilityThreshold", "maximumResponseTokens", "maximumInputTokens", "referenceMode",
                    "contextPolicy", "maximumToolCalls"
                ]
            ),
            "cases": array(
                items: object(
                    properties: [
                        "id": uuid("Stable case UUID."),
                        "name": string("Case name."),
                        "prompt": string("Evaluation prompt.", maximumLength: 32_000),
                        "expected": string("Expected or reference answer.", maximumLength: 32_000)
                    ], required: ["id", "name", "prompt", "expected"]
                ),
                minimum: 1,
                maximum: 100
            )
        ],
        required: [
            "name", "version", "instructions", "scoringMode", "repetitions", "rubricRequirements",
            "modelConfiguration", "cases"
        ]
    )

    private static func object(properties: [String: MCPJSONValue], required: [String]) -> MCPJSONValue {
        .object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(MCPJSONValue.string)),
            "additionalProperties": .bool(false)
        ])
    }

    private static func string(
        _ description: String? = nil,
        enum values: [String]? = nil,
        maximumLength: Int? = nil,
        contentEncoding: String? = nil
    ) -> MCPJSONValue {
        var schema: [String: MCPJSONValue] = ["type": .string("string")]
        if let description { schema["description"] = .string(description) }
        if let values { schema["enum"] = .array(values.map(MCPJSONValue.string)) }
        if let maximumLength { schema["maxLength"] = .integer(Int64(maximumLength)) }
        if let contentEncoding { schema["contentEncoding"] = .string(contentEncoding) }
        return .object(schema)
    }

    private static func uuid(_ description: String) -> MCPJSONValue {
        .object(["type": .string("string"), "format": .string("uuid"), "description": .string(description)])
    }

    private static func boolean(_ description: String? = nil) -> MCPJSONValue {
        var schema: [String: MCPJSONValue] = ["type": .string("boolean")]
        if let description { schema["description"] = .string(description) }
        return .object(schema)
    }

    private static func integer(
        _ description: String? = nil,
        minimum: Int? = nil,
        maximum: Int? = nil
    ) -> MCPJSONValue {
        var schema: [String: MCPJSONValue] = ["type": .string("integer")]
        if let description { schema["description"] = .string(description) }
        if let minimum { schema["minimum"] = .integer(Int64(minimum)) }
        if let maximum { schema["maximum"] = .integer(Int64(maximum)) }
        return .object(schema)
    }

    private static func nullableInteger(minimum: Int, maximum: Int) -> MCPJSONValue {
        .object([
            "anyOf": .array([
                integer(minimum: minimum, maximum: maximum),
                .object(["type": .string("null")])
            ])
        ])
    }

    private static func number(minimum: Double, maximum: Double) -> MCPJSONValue {
        .object([
            "type": .string("number"),
            "minimum": .number(minimum),
            "maximum": .number(maximum)
        ])
    }

    private static func array(items: MCPJSONValue, minimum: Int, maximum: Int) -> MCPJSONValue {
        .object([
            "type": .string("array"),
            "items": items,
            "minItems": .integer(Int64(minimum)),
            "maxItems": .integer(Int64(maximum))
        ])
    }
}

private extension RawRepresentable where RawValue == String, Self: CaseIterable {
    static var allRawValues: [String] { allCases.map(\Self.rawValue) }
}

private extension MCPScoringMode {
    var requiresExpected: Bool {
        self == .exactMatch || self == .containsExpected
    }
}

enum MCPToolInputError: Error {
    case unknownTool
    case invalidArguments
    case confirmationRequired
}
