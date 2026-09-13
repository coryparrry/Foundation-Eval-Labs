import Foundation

struct EvaluationExperimentRunResult: Sendable {
    var current: EvaluationRun
    var candidate: EvaluationRun
}

actor EvaluationExperimentRunner {
    private let runner = EvaluationRunner()

    func run(
        suite: EvaluationSuite,
        experiment: EvaluationExperiment,
        images: [ImageEvaluationInput],
        externalJudge: EvaluationResolvedJudgeConnection?,
        progress: @Sendable (EvaluationSampleResult, Int, Int) async -> Void
    ) async throws -> EvaluationExperimentRunResult {
        let currentRunID = UUID()
        let candidateRunID = UUID()
        let startedAt = Date()
        var currentParts: [EvaluationRun] = []
        var candidateParts: [EvaluationRun] = []

        for (position, variantID) in experiment.executionOrder.enumerated() {
            try Task.checkCancellation()
            let pairIndex = position / 2
            let caseIndex = pairIndex % suite.cases.count
            let repetition = pairIndex / suite.cases.count + 1
            let completedPosition = position + 1
            let variant = variantID == experiment.current.id ? experiment.current : experiment.candidate
            var one = suite
            one.instructions = variant.instructions
            one.cases = [suite.cases[caseIndex]]
            one.repetitions = 1
            var part = await runner.run(
                id: variantID == experiment.current.id ? currentRunID : candidateRunID,
                suiteRevision: variant.suiteRevision ?? experiment.suiteRevision,
                startedAt: startedAt,
                suite: one,
                images: images,
                externalJudge: externalJudge
            ) { result, _, _ in
                var adjusted = result
                adjusted.repetition = repetition
                await progress(adjusted, completedPosition, experiment.executionOrder.count)
            }
            if part.cancelled { throw CancellationError() }
            part.results = part.results.map { result in
                var adjusted = result
                adjusted.repetition = repetition
                return adjusted
            }
            if variantID == experiment.current.id { currentParts.append(part) }
            else { candidateParts.append(part) }
        }

        return .init(
            current: try combined(
                parts: currentParts, id: currentRunID, suite: suite,
                instructions: experiment.current.instructions,
                suiteRevision: experiment.current.suiteRevision ?? experiment.suiteRevision,
                startedAt: startedAt
            ),
            candidate: try combined(
                parts: candidateParts, id: candidateRunID, suite: suite,
                instructions: experiment.candidate.instructions,
                suiteRevision: experiment.candidate.suiteRevision ?? experiment.suiteRevision,
                startedAt: startedAt
            )
        )
    }

    private func combined(
        parts: [EvaluationRun],
        id: UUID,
        suite: EvaluationSuite,
        instructions: String,
        suiteRevision: String,
        startedAt: Date
    ) throws -> EvaluationRun {
        guard var run = parts.first else {
            throw EvaluationStoreError.resourceConflict("The experiment produced no samples.")
        }
        run.id = id
        run.suiteID = suite.id
        run.suiteName = suite.name
        run.suiteVersion = suite.version
        run.instructions = instructions
        run.suiteRevision = suiteRevision
        run.repetitions = suite.repetitions
        run.plannedSampleCount = suite.cases.count * suite.repetitions
        run.plannedCases = suite.cases
        run.startedAt = startedAt
        run.completedAt = Date()
        run.results = parts.flatMap(\.results)
        run.cancelled = false
        run.terminationReason = parts.compactMap(\.terminationReason).first
        var variantSuite = suite
        variantSuite.instructions = instructions
        run.suiteDefinition = EvaluationSuiteDefinition(suite: variantSuite)
        let assessments = parts.flatMap { $0.assessments ?? [] }
        if var assessment = assessments.first {
            assessment.id = UUID()
            assessment.runID = id
            assessment.samples = assessments.flatMap(\.samples)
            assessment.durationMilliseconds = assessments.map(\.durationMilliseconds).reduce(0, +)
            let usage = assessments.compactMap(\.totalUsage)
            assessment.totalUsage = usage.isEmpty ? nil : usage.reduce(into: EvaluationUsage()) { $0.add($1) }
            assessment.cost = combinedCost(assessments.map(\.cost))
            let rawIdentities = assessments.flatMap { $0.observedJudgeIdentities ?? [$0.judge] }
            let modelIdentities = rawIdentities.filter { $0.requestedModelID != "none" }
            let identityCandidates = modelIdentities.isEmpty ? rawIdentities : modelIdentities
            let observedIdentities = identityCandidates.reduce(into: [EvaluationJudgeIdentity]()) { unique, identity in
                if !unique.contains(identity) { unique.append(identity) }
            }
            if let first = observedIdentities.first { assessment.judge = first }
            assessment.observedJudgeIdentities = observedIdentities
            assessment.scoringContract = try? EvaluationScoringContract(suite: variantSuite)
            run.assessments = [assessment]
            run.selectedAssessmentID = assessment.id
        }
        return run
    }

    private func combinedCost(_ costs: [EvaluationCost]) -> EvaluationCost {
        guard costs.allSatisfy({ $0.usd != nil }) else {
            return .init(availability: .unavailable, usd: nil, explanation: "At least one experiment judgment cost was unavailable.")
        }
        let availability: EvaluationCostAvailability = costs.contains { $0.availability == .estimated } ? .estimated : .known
        return .init(
            availability: availability,
            usd: costs.compactMap(\.usd).reduce(0, +),
            explanation: availability == .known ? "Reported by the judge endpoint." : "Estimated from configured token prices."
        )
    }
}
