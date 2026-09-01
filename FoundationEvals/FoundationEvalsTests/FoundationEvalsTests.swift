//
//  FoundationEvalsTests.swift
//  FoundationEvalsTests
//
//  Created by Cory Parry on 01/09/2026.
//

import Testing
@testable import FoundationEvals

struct MetricScorerTests {

    @Test func deterministicMetrics() {
        #expect(MetricScorer.evaluate(mode: .exactMatch, expected: "Paris", response: " Paris\n").status == .passed)
        #expect(MetricScorer.evaluate(mode: .exactMatch, expected: "Paris", response: "Paris, France").status == .failed)
        #expect(MetricScorer.evaluate(mode: .containsExpected, expected: "résumé", response: "The RESUME is attached.").status == .passed)
    }
}
