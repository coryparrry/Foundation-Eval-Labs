import Testing
@testable import FoundationEvals

struct MetricScorerTests {
    @Test func deterministicMetrics() {
        #expect(MetricScorer.evaluate(mode: .exactMatch, expected: "Paris", response: " Paris\n").status == .passed)
        #expect(MetricScorer.evaluate(mode: .exactMatch, expected: "Paris", response: "Paris, France").status == .failed)
        #expect(MetricScorer.evaluate(mode: .containsExpected, expected: "résumé", response: "The RESUME is attached.").status == .passed)
        #expect(MetricScorer.evaluate(mode: .exactMatch, expected: "  ", response: "anything").status == .failed)
        #expect(MetricScorer.evaluate(mode: .containsExpected, expected: "", response: "anything").status == .failed)
    }
}
