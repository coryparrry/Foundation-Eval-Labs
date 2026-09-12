import Foundation
import Security

struct EvaluationResolvedJudgeConnection: Sendable {
    var connection: EvaluationJudgeConnection
    var apiKey: String?
}

struct EvaluationJudgeConnectionCheck: Sendable {
    var checkedAt: Date
    var modelFound: Bool
    var structuredOutputsVerified: Bool?
    var multimodalVerified: Bool?
    var message: String
}

struct EvaluationCompatibleJudgeResult: Sendable {
    var judgment: EvaluationValidatedJudgment
    var trace: EvaluationJudgeTrace
    var identity: EvaluationJudgeIdentity
    var usage: EvaluationUsage?
    var durationMilliseconds: Double
    var cost: EvaluationCost
}

enum EvaluationJudgeCredentialStore {
    private static let service = "com.coryparry.FoundationEvals.judge-connections"

    static func load(connectionID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw EvaluationCompatibleJudgeError.keychain(status)
        }
        return value
    }

    static func save(_ secret: String?, connectionID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString
        ]
        guard let secret, !secret.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw EvaluationCompatibleJudgeError.keychain(status)
            }
            return
        }
        let valueData = Data(secret.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: valueData] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw EvaluationCompatibleJudgeError.keychain(updateStatus)
        }
        let attributes: [String: Any] = query.merging([
            kSecValueData as String: valueData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]) { _, new in new }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw EvaluationCompatibleJudgeError.keychain(status) }
    }
}

actor EvaluationCompatibleJudgeClient {
    static let maximumResponseBytes = 1_048_576

    func checkConnection(_ resolved: EvaluationResolvedJudgeConnection) async throws -> EvaluationJudgeConnectionCheck {
        let connection = resolved.connection
        if let issue = connection.validationIssue { throw EvaluationCompatibleJudgeError.invalidConfiguration(issue) }
        let url = try endpointURL(baseURL: connection.baseURL, component: "models")
        var request = URLRequest(url: url)
        request.timeoutInterval = connection.requestTimeoutSeconds
        applyHeaders(to: &request, resolved: resolved)
        let (data, response) = try await session(timeout: connection.requestTimeoutSeconds).data(for: request)
        try validate(response: response)
        guard data.count <= Self.maximumResponseBytes else { throw EvaluationCompatibleJudgeError.responseTooLarge }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        guard let model = decoded.data.first(where: { $0.id == connection.modelID }) else {
            return .init(
                checkedAt: Date(), modelFound: false,
                structuredOutputsVerified: nil, multimodalVerified: nil,
                message: "The endpoint responded, but did not list model '\(connection.modelID)'."
            )
        }
        let supported = Set(model.supportedParameters ?? [])
        let architecture = Set(model.architecture?.inputModalities ?? [])
        let structured: Bool? = supported.isEmpty ? nil : supported.contains("response_format")
            || supported.contains("structured_outputs")
        let multimodal: Bool? = architecture.isEmpty ? nil : architecture.contains("image")
        if connection.capabilities.structuredOutputs, structured == false {
            throw EvaluationCompatibleJudgeError.capabilityMismatch("The selected endpoint does not advertise structured outputs.")
        }
        if connection.capabilities.multimodal, multimodal == false {
            throw EvaluationCompatibleJudgeError.capabilityMismatch("The selected endpoint does not advertise image input.")
        }
        return .init(
            checkedAt: Date(), modelFound: true,
            structuredOutputsVerified: structured, multimodalVerified: multimodal,
            message: "Connection succeeded for \(connection.modelID). Capabilities without endpoint metadata remain declared, not verified."
        )
    }

    func judge(
        response: String,
        evaluationCase: EvaluationCase,
        effectivePrompt: String,
        suite: EvaluationSuite,
        images: [ImageEvaluationInput],
        toolEvidence: String?,
        resolved: EvaluationResolvedJudgeConnection
    ) async throws -> EvaluationCompatibleJudgeResult {
        let connection = resolved.connection
        if let issue = connection.validationIssue { throw EvaluationCompatibleJudgeError.invalidConfiguration(issue) }
        guard connection.capabilities.structuredOutputs else {
            throw EvaluationCompatibleJudgeError.capabilityMismatch("Structured verdicts are required for judging.")
        }
        guard images.isEmpty || connection.capabilities.multimodal else {
            throw EvaluationCompatibleJudgeError.capabilityMismatch(
                "This evaluation includes image evidence, but the judge connection is not configured and verified for multimodal input."
            )
        }
        guard suite.judgeConfiguration.hasCurrentExternalEvidenceApproval(for: connection) else {
            throw EvaluationCompatibleJudgeError.disclosureNotApproved
        }

        let criteria = suite.rubricCriteria
        guard (1...4).contains(criteria.count) else { throw EvaluationJudgeValidationError.invalidCriteria }
        let started = ContinuousClock.now
        let prompt = EvaluationRunner.judgePrompt(
            response: response,
            evaluationCase: evaluationCase,
            effectivePrompt: effectivePrompt,
            suite: suite,
            toolEvidence: toolEvidence
        )
        var attempts: [EvaluationJudgeAttemptTrace] = []
        var lastError: Error?
        // One bounded repair request is permitted. Every response is validated locally.
        for attempt in 1...2 {
            let repair = attempt == 1 ? nil : """
                The prior response was rejected by the application as incomplete or malformed.
                Return a complete JSON verdict for every numbered requirement. Do not add fields or prose.
                """
            let attemptPrompt = [prompt, repair].compactMap { $0 }.joined(separator: "\n\n")
            attempts.append(.init(prompt: attemptPrompt))
            do {
                let responseEnvelope = try await requestVerdict(
                    prompt: attemptPrompt,
                    criteriaCount: criteria.count,
                    images: suite.judgeConfiguration.includeReferenceAttachments ? images : [],
                    resolved: resolved
                )
                attempts[attempt - 1].rawResponse = responseEnvelope.rawContent
                let verdict = EvaluationJudgeVerdict(checks: responseEnvelope.content.requirements.map {
                    EvaluationJudgeCriterionVerdict(
                        criterionIndex: $0.criterionIndex,
                        score: $0.score,
                        rationale: $0.rationale,
                        exactComparisons: []
                    )
                })
                let judgment = try EvaluationJudge.validate(
                    verdict: verdict,
                    criteria: criteria,
                    response: response,
                    verifiedReference: evaluationCase.expected
                )
                let trace = EvaluationJudgeTrace(
                    instructions: EvaluationRunner.judgeInstructions,
                    prompt: attemptPrompt,
                    rawResponse: responseEnvelope.rawContent,
                    checks: judgment.checks,
                    validationError: nil,
                    attempts: attempts,
                    judgedCriterionIndexes: Array(1...criteria.count)
                )
                return EvaluationCompatibleJudgeResult(
                    judgment: judgment,
                    trace: trace,
                    identity: identity(connection: connection, response: responseEnvelope),
                    usage: responseEnvelope.usage,
                    durationMilliseconds: milliseconds(since: started),
                    cost: cost(connection: connection, response: responseEnvelope)
                )
            } catch {
                lastError = error
                attempts[attempt - 1].validationError = error.localizedDescription
            }
        }
        throw EvaluationCompatibleJudgeError.exhausted(lastError?.localizedDescription ?? "The judge did not return a valid verdict.")
    }

    private func requestVerdict(
        prompt: String,
        criteriaCount: Int,
        images: [ImageEvaluationInput],
        resolved: EvaluationResolvedJudgeConnection
    ) async throws -> CompletionEnvelope {
        let connection = resolved.connection
        let url = try endpointURL(baseURL: connection.baseURL, component: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = connection.requestTimeoutSeconds
        applyHeaders(to: &request, resolved: resolved)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = CompletionRequest(
            model: connection.modelID,
            messages: [
                .init(role: "system", content: .text(EvaluationRunner.judgeInstructions)),
                .init(role: "user", content: try messageContent(prompt: prompt, images: images))
            ],
            responseFormat: .verdict(criteriaCount: criteriaCount),
            temperature: 0,
            stream: false,
            provider: connection.kind == .openRouter
                ? .init(order: connection.providerOrder, allowFallbacks: false, requireParameters: true, dataCollection: "deny")
                : nil
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session(timeout: connection.requestTimeoutSeconds).data(for: request)
        try validate(response: response)
        guard data.count <= Self.maximumResponseBytes else { throw EvaluationCompatibleJudgeError.responseTooLarge }
        let raw = try JSONDecoder().decode(CompletionResponse.self, from: data)
        guard raw.choices.count == 1, let content = raw.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw EvaluationCompatibleJudgeError.missingAssessment
        }
        let verdict = try JSONDecoder().decode(CompatibleVerdict.self, from: contentData)
        let usage = raw.usage.map {
            EvaluationUsage(inputTokens: $0.promptTokens ?? 0, cachedInputTokens: 0,
                            outputTokens: $0.completionTokens ?? 0, reasoningTokens: 0)
        }
        return CompletionEnvelope(
            content: verdict,
            rawContent: content,
            model: raw.model,
            provider: raw.provider,
            usage: usage,
            reportedCost: raw.usage?.cost
        )
    }

    private func messageContent(prompt: String, images: [ImageEvaluationInput]) throws -> MessageContent {
        guard !images.isEmpty else { return .text(prompt) }
        var parts: [ContentPart] = [.text(prompt)]
        for image in images {
            let data = try Data(contentsOf: image.url, options: .mappedIfSafe)
            guard data.count <= EvaluationStore.maximumImageBytes else {
                throw EvaluationCompatibleJudgeError.capabilityMismatch("An image exceeds the evaluation attachment limit.")
            }
            let type = image.url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            parts.append(.image("data:\(type);base64,\(data.base64EncodedString())"))
        }
        return .parts(parts)
    }

    private func endpointURL(baseURL: String, component: String) throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw EvaluationCompatibleJudgeError.invalidConfiguration("The base URL is invalid.")
        }
        let suffix = "/\(component)"
        if !components.path.hasSuffix(suffix) {
            components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = "/" + [components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), component]
                .filter { !$0.isEmpty }.joined(separator: "/")
        }
        guard let url = components.url else {
            throw EvaluationCompatibleJudgeError.invalidConfiguration("The endpoint URL is invalid.")
        }
        return url
    }

    private func applyHeaders(to request: inout URLRequest, resolved: EvaluationResolvedJudgeConnection) {
        if let apiKey = resolved.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if resolved.connection.kind == .openRouter {
            request.setValue("Foundation Evals", forHTTPHeaderField: "X-OpenRouter-Title")
        }
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw EvaluationCompatibleJudgeError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw EvaluationCompatibleJudgeError.http(response.statusCode)
        }
    }

    private func session(timeout: Double) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private func identity(connection: EvaluationJudgeConnection, response: CompletionEnvelope) -> EvaluationJudgeIdentity {
        EvaluationJudgeIdentity(
            mode: .connection,
            connectionID: connection.id,
            connectionName: connection.name,
            endpointKind: connection.kind,
            baseURL: connection.baseURL,
            requestedModelID: connection.modelID,
            reportedModelID: response.model,
            provider: response.provider,
            providerOrder: connection.providerOrder
        )
    }

    private func cost(connection: EvaluationJudgeConnection, response: CompletionEnvelope) -> EvaluationCost {
        if let cost = response.reportedCost {
            return EvaluationCost(availability: .known, usd: cost, explanation: "Reported by the compatible endpoint.")
        }
        if let usage = response.usage,
           let input = connection.inputUSDPerMillionTokens,
           let output = connection.outputUSDPerMillionTokens {
            let estimate = Double(usage.inputTokens) * input / 1_000_000
                + Double(usage.outputTokens) * output / 1_000_000
            return EvaluationCost(availability: .estimated, usd: estimate, explanation: "Estimated from configured token prices.")
        }
        return EvaluationCost(availability: .unavailable, usd: nil, explanation: "The endpoint did not report cost and no token prices are configured.")
    }

    private func milliseconds(since instant: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - instant
        return Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}

private struct CompatibleVerdict: Codable {
    struct Requirement: Codable {
        var criterionIndex: Int
        var score: Int
        var rationale: String
    }
    var requirements: [Requirement]
}

private struct CompletionEnvelope {
    var content: CompatibleVerdict
    var rawContent: String
    var model: String?
    var provider: String?
    var usage: EvaluationUsage?
    var reportedCost: Double?
}

private struct CompletionRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: MessageContent
    }
    struct Provider: Encodable {
        var order: [String]
        var allowFallbacks: Bool
        var requireParameters: Bool
        var dataCollection: String

        enum CodingKeys: String, CodingKey {
            case order
            case allowFallbacks = "allow_fallbacks"
            case requireParameters = "require_parameters"
            case dataCollection = "data_collection"
        }
    }
    var model: String
    var messages: [Message]
    var responseFormat: ResponseFormat
    var temperature: Double
    var stream: Bool
    var provider: Provider?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, provider
        case responseFormat = "response_format"
    }
}

private enum MessageContent: Encodable {
    case text(String)
    case parts([ContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

private struct ContentPart: Encodable {
    var type: String
    var text: String?
    var imageURL: ImageURL?

    struct ImageURL: Encodable { var url: String }

    static func text(_ text: String) -> Self { .init(type: "text", text: text, imageURL: nil) }
    static func image(_ url: String) -> Self { .init(type: "image_url", text: nil, imageURL: .init(url: url)) }

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }
}

private struct ResponseFormat: Encodable {
    struct JSONSchema: Encodable {
        var name: String
        var strict: Bool
        var schema: Schema
    }
    struct Schema: Encodable {
        var type = "object"
        var properties: [String: Property]
        var required: [String]
        var additionalProperties = false
    }
    indirect enum Property: Encodable {
        case string
        case integer(minimum: Int, maximum: Int)
        case array(items: Property, minimum: Int, maximum: Int)
        case object(properties: [String: Property], required: [String])

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            switch self {
            case .string:
                try container.encode("string", forKey: .type)
            case .integer(let minimum, let maximum):
                try container.encode("integer", forKey: .type)
                try container.encode(minimum, forKey: .minimum)
                try container.encode(maximum, forKey: .maximum)
            case .array(let items, let minimum, let maximum):
                try container.encode("array", forKey: .type)
                try container.encode(items, forKey: .items)
                try container.encode(minimum, forKey: .minItems)
                try container.encode(maximum, forKey: .maxItems)
            case .object(let properties, let required):
                try container.encode("object", forKey: .type)
                try container.encode(properties, forKey: .properties)
                try container.encode(required, forKey: .required)
                try container.encode(false, forKey: .additionalProperties)
            }
        }

        enum Keys: String, CodingKey {
            case type, properties, required, items, minimum, maximum, additionalProperties, minItems, maxItems
        }
    }
    var type = "json_schema"
    var jsonSchema: JSONSchema

    static func verdict(criteriaCount: Int) -> Self {
        let requirement = Property.object(
            properties: [
                "criterionIndex": .integer(minimum: 1, maximum: criteriaCount),
                "score": .integer(minimum: 1, maximum: 4),
                "rationale": .string
            ],
            required: ["criterionIndex", "score", "rationale"]
        )
        return Self(jsonSchema: JSONSchema(
            name: "foundation_evals_verdict",
            strict: true,
            schema: Schema(
                properties: ["requirements": .array(items: requirement, minimum: criteriaCount, maximum: criteriaCount)],
                required: ["requirements"]
            )
        ))
    }

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

private struct CompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { var content: String? }
        var message: Message
    }
    struct Usage: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?
        var cost: Double?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case cost
        }
    }
    var choices: [Choice]
    var model: String?
    var provider: String?
    var usage: Usage?
}

private struct ModelsResponse: Decodable {
    struct Model: Decodable {
        struct Architecture: Decodable {
            var inputModalities: [String]?
            enum CodingKeys: String, CodingKey { case inputModalities = "input_modalities" }
        }
        var id: String
        var supportedParameters: [String]?
        var architecture: Architecture?
        enum CodingKeys: String, CodingKey {
            case id, architecture
            case supportedParameters = "supported_parameters"
        }
    }
    var data: [Model]
}

enum EvaluationCompatibleJudgeError: LocalizedError, Sendable {
    case invalidConfiguration(String)
    case disclosureNotApproved
    case capabilityMismatch(String)
    case keychain(OSStatus)
    case invalidResponse
    case http(Int)
    case responseTooLarge
    case missingAssessment
    case exhausted(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .disclosureNotApproved: "Approve the external evidence disclosure for this suite before judging."
        case .capabilityMismatch(let message): message
        case .keychain(let status): "The judge credential could not be read or saved (Keychain status \(status))."
        case .invalidResponse: "The judge endpoint returned a non-HTTP response."
        case .http(let status): "The judge endpoint returned HTTP \(status)."
        case .responseTooLarge: "The judge response exceeded the 1 MB safety limit."
        case .missingAssessment: "The judge response did not contain exactly one assessment."
        case .exhausted(let message): "The judge did not produce a valid verdict after one bounded retry: \(message)"
        }
    }
}
