import Evaluations
import Foundation
import FoundationEvalsAppleBridge
import FoundationEvalsIntegration
import FoundationModels
import Testing
@testable import ConnectedFeature

@Suite(.serialized)
struct NativeCompatibilityTests {
    @Test func exportRoundTripsThroughNativeLoader() async throws {
        ReceiptNativeTrait.counter.reset()
        let directory = FileManager.default.temporaryDirectory.appending(path: "native-result-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try await exportEvaluation(
            ReceiptNativeEvaluation(),
            directory: directory,
            metadata: ["fixture": "controlled-receipt"]
        )
        let data = try CaptureFileIO.readRegularFileNoFollow(
            at: url,
            maximumBytes: CaptureLimits.version1.maximumAppleJSONBytes
        )
        let loaded = try AppleEvaluationCodec.decodeResult(from: data)
        let inspection = try AppleEvaluationCodec.inspect(bytes: data)
        #expect(loaded.resultID == inspection.resultID)
        #expect(inspection.inferenceFailureCount >= 1)
        #expect(inspection.evaluatorFailureCount >= 1)
        #expect(inspection.samples.count == ReceiptNativeEvaluation.samples.count)
        #expect(inspection.samples.contains { $0.subjectError != nil })
        #expect(inspection.samples.contains { $0.evaluatorError != nil })
        #expect(inspection.samples.contains { sample in
            sample.metrics.contains { $0.name == "paidTotal" && $0.kind == "fail" }
        })
        #expect(inspection.samples.contains { sample in
            sample.metrics.contains { $0.name == "penceScale" && $0.kind == "score" }
        })
        #expect(inspection.warnings.contains(where: { $0.contains("Planned coverage unknown") }))
        try persistSanitizedFixture(data, name: "apple-evaluation-result.json")
    }

    @Test(.evaluates(ReceiptNativeEvaluation(counter: ReceiptNativeTrait.counter)))
    func evaluatesTraitDoesNotRunTheEvaluationAgain() {
        #expect(ReceiptNativeTrait.counter.value == ReceiptNativeEvaluation.samples.count)
        let result = EvaluationContext.current.result
        #expect(result.errors.inferenceFailureCount >= 1)
        #expect(result.errors.evaluatorFailureCount >= 1)
    }

    @Test func liveModelUnavailabilityIsExplicit() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            Issue.record("Use liveConnectedFeatureCallsTheModel when the on-device model is available.")
        case .unavailable(let reason):
            #expect(String(describing: reason).isEmpty == false)
        @unknown default:
            Issue.record("Unknown model availability.")
        }
    }

    @Test func liveConnectedFeatureCallsTheModel() async throws {
        guard case .available = SystemLanguageModel.default.availability else {
            return
        }
        let session = LanguageModelSession()
        let response = try await session.respond(to: "Reply with the single word ok.")
        #expect(!response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let bytes = try AppleTranscriptCodec.captureTranscript(from: session)
        let decoded = try AppleTranscriptCodec.decode(from: bytes)
        #expect(Array(decoded).isEmpty == false)
        try persistSanitizedFixture(bytes, name: "apple-transcript.json")
    }

    @Test func emptyTranscriptRoundTripIsNative() throws {
        let bytes = try AppleTranscriptCodec.encode(Transcript())
        let decoded = try AppleTranscriptCodec.decode(from: bytes)
        #expect(Array(decoded).isEmpty)
        try persistSanitizedFixture(bytes, name: "apple-transcript-empty.json")
    }

    private func persistSanitizedFixture(_ data: Data, name: String) throws {
        let fixtures = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        let url = fixtures.appending(path: name)
        try data.write(to: url, options: .atomic)
    }
}
