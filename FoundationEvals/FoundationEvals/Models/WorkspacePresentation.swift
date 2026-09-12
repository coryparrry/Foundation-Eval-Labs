import Foundation

enum SuiteCheckState: String, Sendable {
    case notRun, changed, passed, failed, collected, incomplete, unavailable

    var title: String {
        switch self {
        case .notRun: "Not run"
        case .changed: "Needs a new check"
        case .passed: "Responses passed"
        case .failed: "Needs attention"
        case .collected: "Awaiting assessment"
        case .incomplete: "Incomplete"
        case .unavailable: "Could not load"
        }
    }

    var symbol: String {
        switch self {
        case .notRun: "circle.dashed"
        case .changed: "arrow.trianglehead.clockwise"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .collected: "tray.full"
        case .incomplete: "exclamationmark.circle"
        case .unavailable: "exclamationmark.triangle"
        }
    }

    static func evaluate(run: EvaluationRun?, currentRevision: String, hasDraft: Bool) -> Self {
        guard let run else { return .notRun }
        if hasDraft || run.suiteRevision != currentRevision { return .changed }
        if run.results.isEmpty || run.cancelled || run.stoppedEarly || run.results.count != run.plannedResultCount
            || run.errorCount > 0 || run.results.contains(where: { $0.status == .error })
            || run.selectedAssessment?.samples.contains(where: { $0.status == .error }) == true { return .incomplete }
        if run.scoredCount == 0 { return .collected }
        if run.scoredCount != run.results.count { return .incomplete }
        return run.failedCount > 0 ? .failed : .passed
    }
}

struct SuiteOverviewSummary: Identifiable, Sendable {
    var id: UUID
    var name: String
    var caseCount = 0
    var repetitions = 1
    var state: SuiteCheckState = .notRun
    var latestRunID: UUID?
    var lastCheckedAt: Date?
    var passedCount = 0
    var failedCount = 0
    var errorCount = 0
    var approvedRunID: UUID?
    var hasDraft = false
    var loadError: String?
    var repositoryChanged = false

    init(record: EvaluationSuiteRecord) {
        id = record.id
        name = record.name
    }

    init(record: EvaluationSuiteRecord, suite: EvaluationSuite, currentRevision: String,
         draft: EvaluationSuite?, runs: [EvaluationRun], localState: EvaluationSuiteLocalState) {
        id = record.id
        name = (draft ?? suite).name
        caseCount = (draft ?? suite).cases.count
        repetitions = (draft ?? suite).repetitions
        hasDraft = draft.map { $0 != suite } ?? false
        let run = runs.max { $0.startedAt < $1.startedAt }
        state = SuiteCheckState.evaluate(run: run, currentRevision: currentRevision, hasDraft: hasDraft)
        latestRunID = run?.id
        lastCheckedAt = run?.startedAt
        passedCount = run?.passedCount ?? 0
        failedCount = run?.failedCount ?? 0
        errorCount = run?.errorCount ?? 0
        approvedRunID = localState.baselineApprovals.last { $0.isCurrent }?.runID
    }
}

enum BaselinePresentation {
    static func approvedRun(approval: EvaluationBaselineApproval?, runs: [EvaluationRun]) -> EvaluationRun? {
        guard let approval, var run = runs.first(where: { $0.id == approval.runID }) else { return nil }
        if let assessmentID = approval.assessmentID {
            guard run.assessments?.contains(where: { $0.id == assessmentID }) == true else { return nil }
            run.selectedAssessmentID = assessmentID
        } else {
            // A legacy approval refers to the original scores, before reassessment existed.
            run.assessments = nil
            run.selectedAssessmentID = nil
        }
        return run
    }
}
