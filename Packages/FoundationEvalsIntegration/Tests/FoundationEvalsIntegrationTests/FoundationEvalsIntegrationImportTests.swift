import FoundationEvalsIntegration
import Testing

struct FoundationEvalsIntegrationImportTests {
    private struct EchoFeature: FeatureUnderTest {
        struct Input: Codable, Sendable { var text: String }
        struct Output: Codable, Sendable { var text: String }

        func evaluate(_ input: Input) async throws -> Output {
            Output(text: input.text)
        }
    }

    @Test func publicProductExportsFeatureBoundary() async throws {
        let output = try await EchoFeature().evaluate(.init(text: "ok"))
        #expect(output.text == "ok")
    }
}
