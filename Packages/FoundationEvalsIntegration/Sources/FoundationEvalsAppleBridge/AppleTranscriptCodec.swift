import Foundation
import FoundationEvalsIntegration
import FoundationModels

public struct AppleTranscriptEntryInspection: Sendable, Equatable {
    public var id: String
    public var kind: String
    public var text: String?
    public var toolName: String?
}

public struct AppleTranscriptInspection: Sendable, Equatable {
    public var entries: [AppleTranscriptEntryInspection]
    public var originalByteCount: Int
    public var digest: String
    public var warnings: [String]
}

@available(macOS 27, *)
public enum AppleTranscriptCodec {
    public static func encode(_ transcript: Transcript) throws -> Data {
        try JSONEncoder().encode(transcript)
    }

    public static func decode(from data: Data) throws -> Transcript {
        try JSONDecoder().decode(Transcript.self, from: data)
    }

    public static func inspect(bytes: Data) throws -> AppleTranscriptInspection {
        let transcript = try decode(from: bytes)
        var entries: [AppleTranscriptEntryInspection] = []
        var warnings: [String] = []
        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                entries.append(.init(id: instructions.id, kind: "instructions", text: text(from: instructions.segments), toolName: nil))
            case .prompt(let prompt):
                entries.append(.init(id: prompt.id, kind: "prompt", text: text(from: prompt.segments), toolName: nil))
            case .response(let response):
                entries.append(.init(id: response.id, kind: "response", text: text(from: response.segments), toolName: nil))
            case .toolCalls(let calls):
                for call in calls {
                    entries.append(.init(id: call.id, kind: "toolCall", text: nil, toolName: call.toolName))
                }
            case .toolOutput(let output):
                entries.append(.init(id: output.id, kind: "toolOutput", text: text(from: output.segments), toolName: output.toolName))
            case .reasoning(let reasoning):
                entries.append(.init(id: reasoning.id, kind: "reasoning", text: text(from: reasoning.segments), toolName: nil))
            @unknown default:
                warnings.append("Some fields are available only in the original file")
            }
        }
        if entries.isEmpty {
            warnings.append("Saved conversation evidence · Feature rerun not connected")
        }
        return AppleTranscriptInspection(
            entries: entries,
            originalByteCount: bytes.count,
            digest: CaptureDigest.sha256Hex(bytes),
            warnings: warnings
        )
    }

    public static func captureTranscript(from session: LanguageModelSession) throws -> Data {
        try encode(session.transcript)
    }

    private static func text(from segments: [Transcript.Segment]) -> String {
        segments.compactMap { segment in
            if case .text(let text) = segment { return text.content }
            return nil
        }.joined(separator: "\n")
    }
}
