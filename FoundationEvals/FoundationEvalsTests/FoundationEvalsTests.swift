//
//  FoundationEvalsTests.swift
//  FoundationEvalsTests
//
//  Created by Cory Parry on 01/09/2026.
//

import Foundation
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

    @Test func rubricUsesOneRequirementPerLine() {
        var suite = EvaluationSuite()
        suite.criteria = "\nCorrect facts.\n\nFollows the requested format.\n"

        #expect(suite.rubricCriteria == ["Correct facts.", "Follows the requested format."])
        #expect(EvaluationSuite().rubricCriteria.count == 3)
    }

    @MainActor
    @Test func caseDuplicationAndRunDeletionPreserveSafeDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FoundationEvalsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = EvaluationStore(supportDirectory: directory)
        let original = store.suite.cases[0]

        store.duplicateCase(id: original.id)

        #expect(store.suite.cases.count == 2)
        #expect(store.suite.cases[1].id != original.id)
        #expect(store.suite.cases[1].prompt == original.prompt)
        #expect(store.suite.cases[1].expected == original.expected)
        #expect(store.suite.cases[1].name == "\(original.name) copy")

        let runID = UUID()
        let run = EvaluationRun(
            id: runID,
            suiteID: store.suite.id,
            suiteName: store.suite.name,
            suiteVersion: store.suite.version,
            instructions: store.suite.instructions,
            criteria: store.suite.criteria,
            scoringMode: .review,
            repetitions: 1,
            judgePromptVersion: nil,
            judgePassingScore: nil,
            plannedSampleCount: 5,
            startedAt: .now,
            completedAt: .now,
            cancelled: true,
            terminationReason: "cancelled",
            environment: EvaluationEnvironment(
                operatingSystem: "Test",
                locale: "en_GB",
                model: "Test model",
                modelContextSize: 4096
            ),
            attachments: [],
            results: []
        )
        let runURL = directory
            .appending(path: "Runs", directoryHint: .isDirectory)
            .appending(path: "\(runID.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(run).write(to: runURL, options: .atomic)
        store.runs = [run]
        store.selection = .run(runID)

        #expect(FileManager.default.fileExists(atPath: runURL.path))
        store.deleteRun(id: runID)

        #expect(store.runs.isEmpty)
        #expect(store.selection == .suite)
        #expect(!FileManager.default.fileExists(atPath: runURL.path))
        #expect(EvaluationStore(supportDirectory: directory).runs.isEmpty)
        #expect(run.plannedResultCount == 5)
    }
}
