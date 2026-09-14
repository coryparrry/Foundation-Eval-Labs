import Foundation
import Testing
@testable import FoundationEvals

@MainActor
struct JudgmentCorrectionPersistenceTests {
    @Test func failedCorrectionPersistenceRollsBackCorrectionAndReviewedExample() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let fixture = makeFixture(store: store, promptVersion: EvaluationRunner.judgePromptVersion)
        let suiteDirectory = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory,
            projectID: store.selectedProjectID,
            suiteID: store.selectedSuiteID
        )
        let stateURL = suiteDirectory.appending(path: "state.json")
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        #expect(throws: (any Error).self) {
            try store.markJudgmentIncorrect(
                runID: fixture.run.id,
                assessmentID: fixture.assessment.id,
                sampleID: fixture.run.results[0].id,
                correctedStatus: .failed,
                correctedScore: 2,
                reason: "The judge missed the requirement.",
                collectAsJudgeCheck: true
            )
        }
        #expect(store.suiteLocalState.humanCorrections.isEmpty)
        #expect(store.suiteLocalState.reviewedJudgeExamples.isEmpty)
    }

    @Test func unscoredAndOldPromptCorrectionsPersistOnlyWithoutCollection() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        var fixture = makeFixture(store: store, promptVersion: EvaluationRunner.judgePromptVersion)

        try store.markJudgmentIncorrect(
            runID: fixture.run.id,
            assessmentID: fixture.assessment.id,
            sampleID: fixture.run.results[0].id,
            correctedStatus: .unscored,
            correctedScore: nil,
            reason: "The original response was not scorable.",
            collectAsJudgeCheck: false
        )

        fixture.assessment.promptVersion = "old-judge-prompt"
        fixture.run.assessments = [fixture.assessment]
        store.runs = [fixture.run]
        try store.markJudgmentIncorrect(
            runID: fixture.run.id,
            assessmentID: fixture.assessment.id,
            sampleID: fixture.run.results[0].id,
            correctedStatus: .failed,
            correctedScore: 1,
            reason: "The old prompt is still useful as human review.",
            collectAsJudgeCheck: false
        )

        #expect(store.suiteLocalState.humanCorrections.count == 2)
        #expect(store.suiteLocalState.humanCorrections[0].correctedStatus == .unscored)
        #expect(store.suiteLocalState.humanCorrections[1].correctedStatus == .failed)
        #expect(store.suiteLocalState.reviewedJudgeExamples.isEmpty)
    }

    @Test func unscoredAndOldPromptCorrectionsAreRejectedOnlyWhenCollected() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        var fixture = makeFixture(store: store, promptVersion: EvaluationRunner.judgePromptVersion)

        #expect(throws: EvaluationStoreError.self) {
            try store.markJudgmentIncorrect(
                runID: fixture.run.id,
                assessmentID: fixture.assessment.id,
                sampleID: fixture.run.results[0].id,
                correctedStatus: .unscored,
                correctedScore: nil,
                reason: "Cannot use an unscored check.",
                collectAsJudgeCheck: true
            )
        }

        fixture.assessment.promptVersion = "old-judge-prompt"
        fixture.run.assessments = [fixture.assessment]
        store.runs = [fixture.run]
        #expect(throws: EvaluationStoreError.self) {
            try store.markJudgmentIncorrect(
                runID: fixture.run.id,
                assessmentID: fixture.assessment.id,
                sampleID: fixture.run.results[0].id,
                correctedStatus: .failed,
                correctedScore: 1,
                reason: "Cannot use an old prompt check.",
                collectAsJudgeCheck: true
            )
        }
        #expect(store.suiteLocalState.humanCorrections.isEmpty)
        #expect(store.suiteLocalState.reviewedJudgeExamples.isEmpty)
    }

    private func makeFixture(
        store: EvaluationStore,
        promptVersion: String
    ) -> (run: EvaluationRun, assessment: EvaluationAssessment) {
        let evaluationCase = store.suite.cases[0]
        let now = Date()
        let result = EvaluationSampleResult(
            caseID: evaluationCase.id,
            caseName: evaluationCase.name,
            repetition: 1,
            prompt: evaluationCase.prompt,
            expected: evaluationCase.expected,
            response: "A complete subject response.",
            status: .passed,
            score: 4,
            rationale: nil,
            durationMilliseconds: 1,
            usage: .init(),
            judgeDurationMilliseconds: nil,
            judgeUsage: nil,
            errorCategory: nil,
            errorMessage: nil,
            judgeErrorCategory: nil,
            judgeErrorMessage: nil
        )
        var run = EvaluationRun(
            id: UUID(),
            suiteID: store.suite.id,
            suiteName: store.suite.name,
            suiteVersion: store.suite.version,
            instructions: store.suite.instructions,
            criteria: store.suite.criteria,
            scoringMode: .modelJudge,
            repetitions: 1,
            judgePromptVersion: EvaluationRunner.judgePromptVersion,
            judgePassingScore: EvaluationSuite.judgePassingScore,
            plannedSampleCount: 1,
            suiteRevision: store.suiteRevision,
            plannedCases: store.suite.cases,
            startedAt: now,
            completedAt: now,
            cancelled: false,
            terminationReason: nil,
            environment: .init(operatingSystem: "Test", locale: "en", model: "Fixture", modelContextSize: 1),
            attachments: [],
            results: [result]
        )
        let judge = EvaluationJudgeIdentity(
            mode: .connection,
            connectionID: UUID(),
            connectionName: "Fixture",
            endpointKind: .customCompatible,
            baseURL: "https://judge.example",
            requestedModelID: "judge-v1",
            reportedModelID: "judge-v1",
            provider: "fixture",
            providerOrder: []
        )
        let assessment = EvaluationAssessment(
            id: UUID(),
            runID: run.id,
            createdAt: now,
            origin: .reassessment,
            judge: judge,
            promptVersion: promptVersion,
            rubric: store.suite.criteria,
            passingScore: EvaluationSuite.judgePassingScore,
            samples: [
                .init(
                    id: UUID(),
                    sampleID: result.id,
                    status: .passed,
                    score: 4,
                    rationale: "Fixture",
                    trace: nil,
                    errorCategory: nil,
                    errorMessage: nil,
                    usage: nil,
                    durationMilliseconds: 1
                )
            ],
            totalUsage: nil,
            durationMilliseconds: 1,
            cost: .init(availability: .unavailable, usd: nil, explanation: "Fixture"),
            supersedesAssessmentID: nil,
            scoringContract: try? EvaluationScoringContract(suite: store.suite)
        )
        run.assessments = [assessment]
        run.selectedAssessmentID = assessment.id
        store.runs = [run]
        return (run, assessment)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }
}
