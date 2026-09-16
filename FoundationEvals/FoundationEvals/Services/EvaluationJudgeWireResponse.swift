import Foundation

/// An explicit provider failure is not a malformed verdict and must not trigger
/// a repair request. The client attaches the bounded attempt evidence before
/// propagating it to the runner's normal failure/stop policy.
struct EvaluationJudgeWireFailure: LocalizedError, Sendable {
    enum Kind: Equatable, Sendable { case providerError, incompleteCompletion }
    var kind: Kind
    var message: String
    var attempts: [EvaluationJudgeAttemptTrace] = []

    var errorDescription: String? { message }
}

/// One decoder for compatible JSON and SSE responses. Only optional usage is
/// best-effort: errors, choice shape and completion status remain authoritative.
struct EvaluationJudgeWireResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?

            init(content: String?) { self.content = content }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let text = try? container.decode(String.self, forKey: .content) {
                    content = text
                } else if let parts = try? container.decode([TextPart].self, forKey: .content) {
                    let combined = parts.compactMap(\.text).joined()
                    content = combined.isEmpty ? nil : combined
                } else {
                    content = nil
                }
            }
            private struct TextPart: Decodable { var text: String? }
            private enum CodingKeys: String, CodingKey { case content }
        }
        var message: Message
        var finishReason: String? = nil
        private enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?
        var cost: Double?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            promptTokens = try? container.decode(Int.self, forKey: .promptTokens)
            completionTokens = try? container.decode(Int.self, forKey: .completionTokens)
            cost = try? container.decode(Double.self, forKey: .cost)
        }

        /// Used at both envelope boundaries, including usage-only SSE events.
        static func optional<Key: CodingKey>(
            in container: KeyedDecodingContainer<Key>, forKey key: Key
        ) -> Self? {
            try? container.decodeIfPresent(Self.self, forKey: key)
        }

        var evaluationUsage: EvaluationUsage? {
            guard let promptTokens, promptTokens >= 0,
                  let completionTokens, completionTokens >= 0 else { return nil }
            return EvaluationUsage(inputTokens: promptTokens, cachedInputTokens: 0,
                outputTokens: completionTokens, reasoningTokens: 0)
        }

        var reportedCost: Double? {
            guard evaluationUsage != nil, let cost, cost.isFinite, cost >= 0 else { return nil }
            return cost
        }

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

    init(choices: [Choice], model: String?, provider: String?, usage: Usage?) {
        self.choices = choices
        self.model = model
        self.provider = provider
        self.usage = usage
    }

    init(from decoder: Decoder) throws {
        try Self.rejectExplicitError(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        choices = try container.decode([Choice].self, forKey: .choices)
        for choice in choices { try Self.validateFinishReason(choice.finishReason) }
        model = try container.decodeIfPresent(String.self, forKey: .model)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        usage = Usage.optional(in: container, forKey: .usage)
    }

    private enum CodingKeys: String, CodingKey { case choices, model, provider, usage }
    private enum ErrorKeys: String, CodingKey { case error }
    private struct ProviderError: Decodable { var message: String? }

    private static func rejectExplicitError(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ErrorKeys.self)
        guard container.contains(.error), try !container.decodeNil(forKey: .error) else { return }
        let text = (try? container.decode(ProviderError.self, forKey: .error))?.message
            ?? (try? container.decode(String.self, forKey: .error))
        let detail = text?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let message = detail.flatMap { $0.isEmpty ? nil : String($0.prefix(512)) }
            ?? "The endpoint reported an error without a usable message."
        throw EvaluationJudgeWireFailure(kind: .providerError,
            message: "The judge provider failed: \(message)")
    }

    private static func validateFinishReason(_ reason: String?) throws {
        // Some compatible endpoints omit status. Do not invent success when they
        // DO report a non-successful terminal status, even if content looks valid.
        guard let reason else { return }
        guard reason == "stop" else {
            throw EvaluationJudgeWireFailure(kind: .incompleteCompletion,
                message: "The judge did not complete a verdict (finish_reason: \(String(reason.prefix(128)))).")
        }
    }

    static func decode(from data: Data) throws -> Self {
        let trimmed = data.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
        if trimmed.first == 0x7B { return try JSONDecoder().decode(Self.self, from: data) }
        return try decodeStream(data)
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { var content: String? }
            var delta: Delta?
            var index: Int?
            var finishReason: String?
            private enum CodingKeys: String, CodingKey {
                case delta, index
                case finishReason = "finish_reason"
            }
        }
        var choices: [Choice]
        var model: String?
        var provider: String?
        var usage: Usage?

        init(from decoder: Decoder) throws {
            // Check errors before required choices: error-only events are valid
            // failure messages, not a reason to spend another repair request.
            try EvaluationJudgeWireResponse.rejectExplicitError(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            choices = try container.decode([Choice].self, forKey: .choices)
            guard choices.count <= 1, choices.allSatisfy({ $0.index == nil || $0.index == 0 }) else {
                throw EvaluationJudgeWireFailure(kind: .incompleteCompletion,
                    message: "The judge stream returned unexpected choices for a single verdict.")
            }
            for choice in choices { try EvaluationJudgeWireResponse.validateFinishReason(choice.finishReason) }
            model = try container.decodeIfPresent(String.self, forKey: .model)
            provider = try container.decodeIfPresent(String.self, forKey: .provider)
            usage = Usage.optional(in: container, forKey: .usage)
        }
        private enum CodingKeys: String, CodingKey { case choices, model, provider, usage }
    }

    private static func decodeStream(_ data: Data) throws -> Self {
        var content = ""
        var model: String?
        var provider: String?
        var usage: Usage?
        var sawEvent = false
        var line = Data()
        func consume(_ rawLine: Data) throws {
            var rawLine = rawLine
            if rawLine.last == 0x0D { rawLine.removeLast() }
            guard let text = String(data: rawLine, encoding: .utf8) else {
                throw EvaluationJudgeWireFailure(kind: .incompleteCompletion,
                    message: "The judge stream contained invalid UTF-8.")
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { return }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]" else { return }
            sawEvent = true
            let chunk = try JSONDecoder().decode(StreamChunk.self, from: Data(payload.utf8))
            if let piece = chunk.choices.first?.delta?.content { content += piece }
            model = chunk.model ?? model
            provider = chunk.provider ?? provider
            // A malformed optional telemetry object must not erase usable usage
            // already observed in an earlier event.
            if let incoming = chunk.usage, incoming.evaluationUsage != nil { usage = incoming }
        }
        for byte in data {
            if byte == 0x0A {
                try consume(line)
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
            }
        }
        if !line.isEmpty { try consume(line) }
        guard sawEvent else {
            throw EvaluationJudgeWireFailure(kind: .incompleteCompletion,
                message: "The judge stream contained no completion events.")
        }
        return Self(choices: [.init(message: .init(content: content.isEmpty ? nil : content))],
            model: model, provider: provider, usage: usage)
    }
}
