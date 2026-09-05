import Foundation
import FoundationModels

struct EvaluationFeatureTrace: Codable, Sendable {
    var customToolCalls: [EvaluationCustomToolCallTrace] = []
    var profileEvents: [String] = []
    var firstContentMilliseconds: Double? = nil
}

struct EvaluationFeatureResponse {
    var content: String
    var usage: LanguageModelSession.Usage
    var transcriptEntries: [Transcript.Entry]
    var firstContentMilliseconds: Double?

    static func generate(
        session: LanguageModelSession,
        prompt: Prompt,
        suite: EvaluationSuite,
        metadata: [String: any ConvertibleToGeneratedContent]
    ) async throws -> Self {
        var options = suite.modelConfiguration.generationOptions
        // A dynamic profile supplies its own changing tool policy.
        options.toolCallingMode = suite.features.profile.enabled ? nil
            : (suite.features.tools.isEmpty && suite.modelConfiguration.referenceMode != .lookupTool
                ? .disallowed : .allowed)
        var context = suite.modelConfiguration.contextOptions
        context.includeSchemaInPrompt = true
        let schema = suite.features.outputFields.isEmpty ? nil
            : try EvaluationSchemaBuilder.schema(fields: suite.features.outputFields, name: "EvaluationOutput")
        if suite.features.streamResponse {
            if let schema {
                return try await collect(
                    session.streamResponse(to: prompt, schema: schema, options: options,
                                           contextOptions: context, metadata: metadata),
                    text: { $0.rawContent.jsonString },
                    finalText: { $0.jsonString }
                )
            }
            return try await collect(
                session.streamResponse(to: prompt, options: options, contextOptions: context, metadata: metadata),
                text: { $0.content }, finalText: { $0 }
            )
        }
        if let schema {
            let response = try await session.respond(to: prompt, schema: schema, options: options,
                                                     contextOptions: context, metadata: metadata)
            return Self(content: response.content.jsonString, usage: response.usage,
                        transcriptEntries: Array(response.transcriptEntries))
        }
        let response = try await session.respond(to: prompt, options: options,
                                                 contextOptions: context, metadata: metadata)
        return Self(content: response.content, usage: response.usage,
                    transcriptEntries: Array(response.transcriptEntries))
    }

    private static func collect<Content: Generable>(
        _ stream: LanguageModelSession.ResponseStream<Content>,
        text: (LanguageModelSession.ResponseStream<Content>.Snapshot) -> String,
        finalText: (Content) -> String
    ) async throws -> Self {
        let started = ContinuousClock.now
        var firstContent: Double?
        for try await snapshot in stream {
            try Task.checkCancellation()
            let visible = text(snapshot).trimmingCharacters(in: .whitespacesAndNewlines)
            if firstContent == nil, !visible.isEmpty, visible != "{}", visible != "null" {
                let elapsed = started.duration(to: .now).components
                firstContent = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
            }
        }
        let response = try await stream.collect()
        return Self(content: finalText(response.content), usage: response.usage,
                    transcriptEntries: Array(response.transcriptEntries),
                    firstContentMilliseconds: firstContent)
    }
}
