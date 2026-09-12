import Foundation

enum EvaluationExperimentAnalyzer {
    static func summarize(
        current: EvaluationRun,
        candidate: EvaluationRun
    ) -> EvaluationExperimentSummary {
        let currentByCase = Dictionary(grouping: current.results, by: \.caseID)
        let candidateByCase = Dictionary(grouping: candidate.results, by: \.caseID)
        let common = Set(currentByCase.keys).intersection(candidateByCase.keys)
        var improved: [UUID] = []
        var regressed: [UUID] = []
        var unchanged: [UUID] = []
        for id in common {
            let currentRate = passRate(currentByCase[id] ?? [])
            let candidateRate = passRate(candidateByCase[id] ?? [])
            guard let currentRate, let candidateRate else { continue }
            if candidateRate > currentRate { improved.append(id) }
            else if candidateRate < currentRate { regressed.append(id) }
            else { unchanged.append(id) }
        }

        let discordant = improved.count + regressed.count
        let interval = discordant == 0 ? nil : wilsonInterval(successes: improved.count, total: discordant)
        let decision: EvaluationExperimentDecision
        let explanation: String
        if common.count < 3 || discordant < 2 {
            decision = .collectMoreEvidence
            explanation = "Too few distinct comparable cases changed outcome to justify a winner. Repetitions improve stability but do not add case coverage."
        } else if let interval, interval.lowerBound > 0.5 {
            decision = .adoptCandidate
            explanation = "The candidate improved a majority of discordant cases and the case-level 95% interval excludes an even split."
        } else if let interval, interval.upperBound < 0.5 {
            decision = .keepCurrent
            explanation = "The current variant won a majority of discordant cases and the case-level 95% interval excludes an even split."
        } else {
            decision = .inconclusive
            explanation = "Observed case-level changes do not provide sufficient evidence to choose a winner."
        }

        return EvaluationExperimentSummary(
            improvedCaseIDs: improved.sorted { $0.uuidString < $1.uuidString },
            regressedCaseIDs: regressed.sorted { $0.uuidString < $1.uuidString },
            unchangedCaseIDs: unchanged.sorted { $0.uuidString < $1.uuidString },
            currentMedianLatencyMilliseconds: median(current.results.map(\.durationMilliseconds)),
            candidateMedianLatencyMilliseconds: median(candidate.results.map(\.durationMilliseconds)),
            distinctCaseCoverage: common.count,
            repetitionsPerCase: min(current.repetitions, candidate.repetitions),
            confidenceInterval: interval,
            suggestedDecision: decision,
            explanation: explanation
        )
    }

    static func balancedOrder(
        currentID: UUID,
        candidateID: UUID,
        caseCount: Int,
        repetitions: Int
    ) -> [UUID] {
        guard caseCount > 0, repetitions > 0 else { return [] }
        return (0..<(caseCount * repetitions)).flatMap { index in
            index.isMultiple(of: 2) ? [currentID, candidateID] : [candidateID, currentID]
        }
    }

    private static func passRate(_ results: [EvaluationSampleResult]) -> Double? {
        let scored = results.filter { $0.status == .passed || $0.status == .failed }
        guard !scored.isEmpty else { return nil }
        return Double(scored.count { $0.status == .passed }) / Double(scored.count)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    /// Wilson score interval over distinct discordant cases. Repetitions are first
    /// aggregated within a case and are never counted as independent evidence.
    private static func wilsonInterval(successes: Int, total: Int) -> ClosedRange<Double> {
        let z = 1.959963984540054
        let n = Double(total)
        let p = Double(successes) / n
        let denominator = 1 + z * z / n
        let centre = (p + z * z / (2 * n)) / denominator
        let margin = z * sqrt((p * (1 - p) + z * z / (4 * n)) / n) / denominator
        return max(0, centre - margin)...min(1, centre + margin)
    }
}

enum EvaluationReleaseCheckEvaluator {
    static func report(
        projectID: UUID,
        suite: EvaluationSuite,
        currentSuiteRevision: String,
        run: EvaluationRun?,
        baseline: EvaluationRun?,
        approvedBaseline: EvaluationBaselineApproval?
    ) -> EvaluationReleaseCheckReport {
        var incomplete: [String] = []
        var regressions: [String] = []
        var execution: [String] = []
        let policy = suite.releasePolicy
        if !(0...(EvaluationStore.maximumPlannedSamples * 2)).contains(policy.maximumErrorCount)
            || !policy.maximumPassRateRegression.isFinite
            || !(0...1).contains(policy.maximumPassRateRegression)
            || policy.maximumAverageLatencyMilliseconds.map({ !$0.isFinite || $0 < 0 }) == true
            || Set(policy.criticalCaseIDs).count != policy.criticalCaseIDs.count
            || !Set(policy.criticalCaseIDs).isSubset(of: Set(suite.cases.map(\.id))) {
            incomplete.append("The suite's release policy is invalid and must be corrected before it can pass.")
        }

        guard let run else {
            return EvaluationReleaseCheckReport(
                projectID: projectID,
                suiteID: suite.id,
                runID: nil,
                assessmentID: nil,
                outcome: .incompleteOrIncompatibleEvidence,
                summary: "No completed run is available for this required suite.",
                failures: ["Run the suite using its current saved definition."],
                generatedAt: Date()
            )
        }
        if run.cancelled || run.stoppedEarly || run.results.count < run.plannedResultCount {
            incomplete.append("The run did not complete every planned sample.")
        }
        if run.suiteID != suite.id {
            incomplete.append("The run belongs to a different suite.")
        }
        if run.scoringMode != suite.scoringMode {
            incomplete.append("The run used a different scoring mode from the current suite.")
        }
        if run.suiteRevision == nil || run.suiteRevision != currentSuiteRevision {
            incomplete.append("The run is stale because the suite definition changed.")
        }
        if run.scoringMode == .modelJudge {
            let resultIDs = Set(run.results.map(\.id))
            if run.selectedAssessment.map({ assessment in
                assessment.runID == run.id
                    && assessment.samples.count == run.results.count
                    && Set(assessment.samples.map(\.sampleID)) == resultIDs
                    && assessment.samples.allSatisfy({ $0.status == .passed || $0.status == .failed })
            }) != true {
                incomplete.append("The selected judge assessment is missing, incomplete, or contains unscored evidence.")
            }
            if let assessment = run.selectedAssessment,
               (assessment.observedJudgeIdentities ?? [assessment.judge]).count != 1 {
                incomplete.append("The selected assessment contains mixed judge model or provider identities.")
            }
        }
        if run.scoredCount != run.results.count {
            incomplete.append("The run does not contain pass/fail evidence for every completed sample.")
        }
        if run.errorCount > policy.maximumErrorCount {
            execution.append("The run has \(run.errorCount) errors; the limit is \(policy.maximumErrorCount).")
        }
        if let maximum = policy.maximumAverageLatencyMilliseconds,
           run.averageDurationMilliseconds > maximum {
            regressions.append("Average latency \(Int(run.averageDurationMilliseconds)) ms exceeds the \(Int(maximum)) ms limit.")
        }
        let selectedStatusBySampleID = Dictionary(
            uniqueKeysWithValues: (run.selectedAssessment?.samples ?? []).map { ($0.sampleID, $0.status) }
        )
        for caseID in policy.criticalCaseIDs {
            let results = run.results.filter { $0.caseID == caseID }
            if results.isEmpty || results.contains(where: {
                (selectedStatusBySampleID[$0.id] ?? $0.status) != .passed
            }) {
                regressions.append("Critical case \(caseID.uuidString) did not pass every trial.")
            }
        }

        if policy.requireApprovedBaseline {
            guard let approvedBaseline else {
                incomplete.append("This suite requires an explicitly approved baseline.")
                return result(projectID: projectID, suite: suite, run: run,
                              incomplete: incomplete, regressions: regressions, execution: execution)
            }
            guard approvedBaseline.isCurrent,
                  approvedBaseline.suiteRevision == currentSuiteRevision,
                  let baseline,
                  baseline.id == approvedBaseline.runID else {
                incomplete.append("The approved baseline run is missing or no longer current.")
                return result(projectID: projectID, suite: suite, run: run,
                              incomplete: incomplete, regressions: regressions, execution: execution)
            }
            var approvedBaselineRun = baseline
            if baseline.scoringMode == .modelJudge {
                guard let assessmentID = approvedBaseline.assessmentID,
                      let approvedAssessment = baseline.assessments?.first(where: { $0.id == assessmentID }),
                      (approvedAssessment.observedJudgeIdentities ?? [approvedAssessment.judge]).count == 1 else {
                    incomplete.append("The approved baseline assessment is missing or contains mixed judge identities.")
                    return result(projectID: projectID, suite: suite, run: run,
                                  incomplete: incomplete, regressions: regressions, execution: execution)
                }
                approvedBaselineRun.selectedAssessmentID = assessmentID
            }
            let comparison = EvaluationRunComparison(current: run, baseline: approvedBaselineRun)
            guard comparison.compatibility == .compatible else {
                incomplete.append("The current run and approved baseline use incompatible comparison conditions.")
                return result(projectID: projectID, suite: suite, run: run,
                              incomplete: incomplete, regressions: regressions, execution: execution)
            }
            if let currentJudge = run.selectedAssessment?.judge,
               let baselineJudge = approvedBaselineRun.selectedAssessment?.judge,
               currentJudge != baselineJudge {
                incomplete.append("Judge conditions changed. Reassess both runs with the same fixed judge before comparison.")
            }
            if let currentRate = run.passRate, let baselineRate = approvedBaselineRun.passRate,
               baselineRate - currentRate > policy.maximumPassRateRegression {
                regressions.append("Pass rate regressed by \((baselineRate - currentRate).formatted(.percent.precision(.fractionLength(1)))).")
            }
        }
        return result(projectID: projectID, suite: suite, run: run,
                      incomplete: incomplete, regressions: regressions, execution: execution)
    }

    static func markdown(_ report: EvaluationReleaseCheckReport) -> String {
        let heading = report.outcome == .passed ? "Release check passed" : "Release check did not pass"
        let failures = report.failures.isEmpty ? "- None" : report.failures.map { "- \($0)" }.joined(separator: "\n")
        return """
        # \(heading)

        \(report.summary)

        - Project: `\(report.projectID.uuidString)`
        - Suite: `\(report.suiteID.uuidString)`
        - Run: `\(report.runID?.uuidString ?? "unavailable")`
        - Assessment: `\(report.assessmentID?.uuidString ?? "unavailable")`
        - Exit status: `\(report.outcome.rawValue)`

        ## Findings

        \(failures)
        """
    }

    private static func result(
        projectID: UUID,
        suite: EvaluationSuite,
        run: EvaluationRun,
        incomplete: [String],
        regressions: [String],
        execution: [String]
    ) -> EvaluationReleaseCheckReport {
        let outcome: EvaluationReleaseCheckExit
        let failures: [String]
        if !execution.isEmpty {
            outcome = .executionError
            failures = execution + incomplete + regressions
        } else if !incomplete.isEmpty {
            outcome = .incompleteOrIncompatibleEvidence
            failures = incomplete + regressions
        } else if !regressions.isEmpty {
            outcome = .regression
            failures = regressions
        } else {
            outcome = .passed
            failures = []
        }
        return EvaluationReleaseCheckReport(
            projectID: projectID,
            suiteID: suite.id,
            runID: run.id,
            assessmentID: run.selectedAssessmentID,
            outcome: outcome,
            summary: outcome == .passed ? "All configured release requirements passed." : "One or more release requirements were not satisfied.",
            failures: failures,
            generatedAt: Date()
        )
    }
}
