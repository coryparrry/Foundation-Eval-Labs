import Foundation
import FoundationEvalsIntegration
import FoundationModels
import Testing

struct AppleTranscriptCodecTests {
    @Test func emptyTranscriptRoundTrips() throws {
        let transcript = Transcript()
        let data = try AppleTranscriptCodec.encode(transcript)
        let decoded = try AppleTranscriptCodec.decode(from: data)
        let inspection = try AppleTranscriptCodec.inspect(bytes: data)
        #expect(decoded == transcript)
        #expect(inspection.originalByteCount == data.count)
        #expect(inspection.warnings.contains("Saved conversation evidence · Feature rerun not connected"))
    }
}
