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
            let session = LanguageModelSession()
            let bytes = try AppleTranscriptCodec.captureTranscript(from: session)
            let decoded = try AppleTranscriptCodec.decode(from: bytes)
            #expect(Array(decoded).count == Array(session.transcript).count)
            try persistSanitizedFixture(bytes, name: "apple-transcript.json")
        case .unavailable(let reason):
            #expect(String(describing: reason).isEmpty == false)
        @unknown default:
            Issue.record("Unknown model availability.")
        }
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
