import Foundation
import FoundationModels

enum EvaluationSchemaBuilder {
    static func schema(
        fields: [EvaluationSchemaField],
        name: String
    ) throws -> GenerationSchema {
        guard EvaluationIdentifier.isValid(
            name,
            maximumCharacters: EvaluationCustomToolDefinition.maximumNameCharacters
        ) else {
            throw EvaluationFeatureConfigurationError.invalid(
                "Schema names must be identifiers of \(EvaluationCustomToolDefinition.maximumNameCharacters) characters or fewer."
            )
        }
        guard fields.count <= EvaluationCustomToolDefinition.maximumParameters else {
            throw EvaluationFeatureConfigurationError.invalid(
                "A schema can define at most \(EvaluationCustomToolDefinition.maximumParameters) fields."
            )
        }
        if let issue = EvaluationFeatureConfiguration.schemaValidationIssue(
            fields: fields,
            context: "Schema \(name)"
        ) {
            throw EvaluationFeatureConfigurationError.invalid(issue)
        }

        let properties = fields.map { field in
            DynamicGenerationSchema.Property(
                name: field.name,
                description: field.description.isEmpty ? nil : field.description,
                schema: dynamicSchema(for: field.type),
                isOptional: field.isOptional
            )
        }
        let root = DynamicGenerationSchema(name: name, properties: properties)
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func dynamicSchema(
        for type: EvaluationSchemaFieldType
    ) -> DynamicGenerationSchema {
        switch type {
        case .string: DynamicGenerationSchema(type: String.self)
        case .integer: DynamicGenerationSchema(type: Int.self)
        case .number: DynamicGenerationSchema(type: Double.self)
        case .boolean: DynamicGenerationSchema(type: Bool.self)
        }
    }
}

enum EvaluationCustomToolCallOutcome: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case failed
    case cancelled
    case rejected
}

struct EvaluationCustomToolCallTrace: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var toolName: String
    var argumentsJSON: String
    var output: String?
    var durationMilliseconds: Double
    var outcome: EvaluationCustomToolCallOutcome
    var errorDescription: String?
}

actor EvaluationCustomToolRecorder {
    static let maximumCallsPerSample = 4
    private static let maximumErrorBytes = 1_024
    private static let maximumRecordedRejections = 4

    let maximumCalls: Int
    private var acceptedCallCount = 0
    private var rejectedCallCount = 0
    private var traces: [EvaluationCustomToolCallTrace] = []

    init(maximumCalls: Int) {
        self.maximumCalls = min(max(0, maximumCalls), Self.maximumCallsPerSample)
    }

    func beginCall(toolName: String, argumentsJSON: String) throws -> UUID {
        guard acceptedCallCount < maximumCalls else {
            if rejectedCallCount < Self.maximumRecordedRejections {
                rejectedCallCount += 1
                traces.append(
                    EvaluationCustomToolCallTrace(
                        id: UUID(),
                        toolName: toolName,
                        argumentsJSON: argumentsJSON.boundedUTF8(
                            to: EvaluationCustomToolDefinition.maximumArgumentBytes
                        ),
                        output: nil,
                        durationMilliseconds: 0,
                        outcome: .rejected,
                        errorDescription: "The run reached its \(maximumCalls)-call custom tool limit."
                    )
                )
            }
            throw EvaluationCustomToolError.callLimitReached(maximum: maximumCalls)
        }

        acceptedCallCount += 1
        let id = UUID()
        traces.append(
            EvaluationCustomToolCallTrace(
                id: id,
                toolName: toolName,
                argumentsJSON: argumentsJSON.boundedUTF8(
                    to: EvaluationCustomToolDefinition.maximumArgumentBytes
                ),
                output: nil,
                durationMilliseconds: 0,
                outcome: .running,
                errorDescription: nil
            )
        )
        return id
    }

    func finishCall(
        id: UUID,
        output: String?,
        durationMilliseconds: Double,
        outcome: EvaluationCustomToolCallOutcome,
        errorDescription: String? = nil
    ) {
        guard let index = traces.firstIndex(where: { $0.id == id }) else { return }
        traces[index].output = output?.boundedUTF8(
            to: EvaluationCustomToolDefinition.maximumOutputBytes
        )
        traces[index].durationMilliseconds = max(0, durationMilliseconds)
        traces[index].outcome = outcome
        traces[index].errorDescription = errorDescription?.boundedUTF8(
            to: Self.maximumErrorBytes
        )
    }

    func snapshot() -> [EvaluationCustomToolCallTrace] {
        traces
    }

    func evidenceText() -> String {
        guard !traces.isEmpty else { return "No custom tools were called." }

        return traces.enumerated().map { index, trace in
            var lines = [
                "Custom tool call \(index + 1): \(trace.toolName)",
                "Outcome: \(trace.outcome.rawValue)",
                "Arguments: \(trace.argumentsJSON)",
                "Duration: \(trace.durationMilliseconds.formatted(.number.precision(.fractionLength(1)))) ms"
            ]
            if let output = trace.output {
                lines.append("Output: \(output)")
            }
            if let errorDescription = trace.errorDescription {
                lines.append("Error: \(errorDescription)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

struct EvaluationCustomTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    static let maximumArgumentTokens = 256
    static let maximumOutputTokens = 512
    static let contextTokenReservePerCall = 1_024

    let name: String
    let description: String
    let parameters: GenerationSchema

    private let definition: EvaluationCustomToolDefinition
    private let recorder: EvaluationCustomToolRecorder
    private let httpClient: any EvaluationCustomToolHTTPClient
    private let tokenCounter: any EvaluationCustomToolTokenCounting

    init(
        definition: EvaluationCustomToolDefinition,
        recorder: EvaluationCustomToolRecorder
    ) throws {
        try self.init(
            definition: definition,
            recorder: recorder,
            httpClient: EvaluationLocalHTTPToolClient(),
            tokenCounter: EvaluationSystemModelTokenCounter()
        )
    }

    init(
        definition: EvaluationCustomToolDefinition,
        recorder: EvaluationCustomToolRecorder,
        httpClient: any EvaluationCustomToolHTTPClient,
        tokenCounter: any EvaluationCustomToolTokenCounting = EvaluationSystemModelTokenCounter()
    ) throws {
        if let issue = definition.validationIssue {
            throw EvaluationFeatureConfigurationError.invalid(issue)
        }
        self.name = definition.name
        self.description = definition.description
        self.parameters = try EvaluationSchemaBuilder.schema(
            fields: definition.parameters,
            name: definition.name
        )
        self.definition = definition
        self.recorder = recorder
        self.httpClient = httpClient
        self.tokenCounter = tokenCounter
    }

    static func makeTools(
        definitions: [EvaluationCustomToolDefinition],
        recorder: EvaluationCustomToolRecorder
    ) throws -> [EvaluationCustomTool] {
        guard definitions.count <= EvaluationFeatureConfiguration.maximumTools else {
            throw EvaluationFeatureConfigurationError.invalid(
                "A suite can define at most \(EvaluationFeatureConfiguration.maximumTools) custom tools."
            )
        }
        let configuration = EvaluationFeatureConfiguration(tools: definitions)
        if let issue = configuration.validationIssue {
            throw EvaluationFeatureConfigurationError.invalid(issue)
        }
        return try definitions.map { try EvaluationCustomTool(definition: $0, recorder: recorder) }
    }

    @concurrent
    func call(arguments: GeneratedContent) async throws -> String {
        let argumentsJSON = arguments.jsonString
        let callID = try await recorder.beginCall(toolName: name, argumentsJSON: argumentsJSON)
        let start = ContinuousClock.now
        var observedOutput: String?

        do {
            let requestBody = try Self.requestBody(
                toolName: name,
                argumentsJSON: argumentsJSON
            )
            let argumentTokenCount = try await tokenCounter.tokenCount(for: argumentsJSON)
            guard argumentTokenCount <= Self.maximumArgumentTokens else {
                throw EvaluationCustomToolError.argumentTokenLimitExceeded(
                    actual: argumentTokenCount,
                    maximum: Self.maximumArgumentTokens
                )
            }
            try Task.checkCancellation()

            let output: String
            switch definition.mode {
            case .fixture:
                output = definition.fixtureResponse
            case .localHTTP:
                output = try await httpClient.post(
                    body: requestBody,
                    to: definition.validatedEndpointURL()
                )
            }
            observedOutput = output
            guard output.utf8.count <= EvaluationCustomToolDefinition.maximumOutputBytes else {
                throw EvaluationCustomToolError.outputTooLarge
            }
            let outputTokenCount = try await tokenCounter.tokenCount(for: output)
            guard outputTokenCount <= Self.maximumOutputTokens else {
                throw EvaluationCustomToolError.outputTokenLimitExceeded(
                    actual: outputTokenCount,
                    maximum: Self.maximumOutputTokens
                )
            }

            await recorder.finishCall(
                id: callID,
                output: output,
                durationMilliseconds: start.milliseconds(to: .now),
                outcome: .succeeded
            )
            return output
        } catch is CancellationError {
            await recorder.finishCall(
                id: callID,
                output: observedOutput,
                durationMilliseconds: start.milliseconds(to: .now),
                outcome: .cancelled,
                errorDescription: "The custom tool call was cancelled."
            )
            throw CancellationError()
        } catch {
            let outcome: EvaluationCustomToolCallOutcome
            if error is EvaluationCustomToolRejectedError {
                outcome = .rejected
            } else if let toolError = error as? EvaluationCustomToolError,
                      toolError.isPolicyRejection {
                outcome = .rejected
            } else {
                outcome = .failed
            }
            await recorder.finishCall(
                id: callID,
                output: observedOutput,
                durationMilliseconds: start.milliseconds(to: .now),
                outcome: outcome,
                errorDescription: error.localizedDescription
            )
            throw error
        }
    }

    static func requestBody(toolName: String, argumentsJSON: String) throws -> Data {
        let argumentsData = Data(argumentsJSON.utf8)
        guard argumentsData.count <= EvaluationCustomToolDefinition.maximumArgumentBytes else {
            throw EvaluationCustomToolRejectedError.argumentsTooLarge
        }

        let arguments = try JSONSerialization.jsonObject(with: argumentsData)
        guard let object = arguments as? [String: Any] else {
            throw EvaluationCustomToolRejectedError.argumentsMustBeObject
        }
        let body = try JSONSerialization.data(
            withJSONObject: ["toolName": toolName, "arguments": object],
            options: [.sortedKeys]
        )
        guard body.count <= EvaluationCustomToolDefinition.maximumArgumentBytes else {
            throw EvaluationCustomToolRejectedError.argumentsTooLarge
        }
        return body
    }
}

protocol EvaluationCustomToolHTTPClient: Sendable {
    func post(body: Data, to endpoint: URL) async throws -> String
}

protocol EvaluationCustomToolTokenCounting: Sendable {
    func tokenCount(for text: String) async throws -> Int
}

struct EvaluationSystemModelTokenCounter: EvaluationCustomToolTokenCounting {
    func tokenCount(for text: String) async throws -> Int {
        try await SystemLanguageModel.default.tokenCount(for: Prompt(text))
    }
}

struct EvaluationLocalHTTPToolClient: EvaluationCustomToolHTTPClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = EvaluationCustomToolDefinition.requestTimeoutSeconds
        configuration.timeoutIntervalForResource = EvaluationCustomToolDefinition.requestTimeoutSeconds
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.connectionProxyDictionary = [:]
        session = URLSession(
            configuration: configuration,
            delegate: EvaluationNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    init(session: URLSession) {
        self.session = session
    }

    func post(body: Data, to endpoint: URL) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = EvaluationCustomToolDefinition.requestTimeoutSeconds
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw EvaluationCustomToolError.invalidHTTPResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw EvaluationCustomToolError.httpStatus(response.statusCode)
        }

        var data = Data()
        data.reserveCapacity(EvaluationCustomToolDefinition.maximumOutputBytes)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < EvaluationCustomToolDefinition.maximumOutputBytes else {
                throw EvaluationCustomToolError.outputTooLarge
            }
            data.append(byte)
        }
        guard let output = String(data: data, encoding: .utf8) else {
            throw EvaluationCustomToolError.invalidOutputEncoding
        }
        return output
    }
}

final class EvaluationNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum EvaluationCustomToolError: LocalizedError, Sendable {
    case callLimitReached(maximum: Int)
    case outputTooLarge
    case argumentTokenLimitExceeded(actual: Int, maximum: Int)
    case outputTokenLimitExceeded(actual: Int, maximum: Int)
    case invalidHTTPResponse
    case httpStatus(Int)
    case invalidOutputEncoding

    var errorDescription: String? {
        switch self {
        case .callLimitReached(let maximum):
            "The run reached its \(maximum)-call custom tool limit."
        case .outputTooLarge:
            "The custom tool output exceeded \(EvaluationCustomToolDefinition.maximumOutputBytes) bytes."
        case .argumentTokenLimitExceeded(let actual, let maximum):
            "The custom tool arguments used \(actual) tokens, exceeding the \(maximum)-token argument limit."
        case .outputTokenLimitExceeded(let actual, let maximum):
            "The custom tool output used \(actual) tokens, exceeding the \(maximum)-token output limit."
        case .invalidHTTPResponse:
            "The custom tool endpoint did not return an HTTP response."
        case .httpStatus(let status):
            "The custom tool endpoint returned HTTP \(status)."
        case .invalidOutputEncoding:
            "The custom tool endpoint returned output that is not UTF-8."
        }
    }

    fileprivate var isPolicyRejection: Bool {
        switch self {
        case .outputTooLarge, .argumentTokenLimitExceeded, .outputTokenLimitExceeded:
            true
        case .callLimitReached, .invalidHTTPResponse, .httpStatus, .invalidOutputEncoding:
            false
        }
    }
}

private enum EvaluationCustomToolRejectedError: LocalizedError, Sendable {
    case argumentsTooLarge
    case argumentsMustBeObject

    var errorDescription: String? {
        switch self {
        case .argumentsTooLarge:
            "The custom tool request exceeded \(EvaluationCustomToolDefinition.maximumArgumentBytes) bytes."
        case .argumentsMustBeObject:
            "Custom tool arguments must be a JSON object."
        }
    }
}

private extension ContinuousClock.Instant {
    func milliseconds(to end: ContinuousClock.Instant) -> Double {
        let components = duration(to: end).components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private extension String {
    func boundedUTF8(to maximumBytes: Int) -> String {
        let bytes = utf8
        guard bytes.count > maximumBytes else { return self }
        return String(decoding: bytes.prefix(maximumBytes), as: UTF8.self)
    }
}
