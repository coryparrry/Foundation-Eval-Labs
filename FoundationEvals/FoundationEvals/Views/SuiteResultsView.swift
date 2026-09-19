import SwiftUI

struct SuiteResultsView: View {
    @Bindable var store: EvaluationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Run history").font(.title2.weight(.bold))
                    Text("Every run, with the evidence behind it.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.runs.count) saved").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                if store.runs.isEmpty {
                    WorkspaceEmptyState(symbol: "chart.bar.doc.horizontal", title: "Ready for your first run",
                                        detail: "Run this suite to collect responses, scores, and execution traces. Your results will appear here.")
                } else {
                    ForEach(store.runs) { run in
                        let state = SuiteCheckState.evaluate(run: run, currentRevision: store.suiteRevision,
                                                             hasDraft: store.draftSuite != store.suite)
                        Button { store.selection = .run(run.id) } label: {
                            WorkspaceRunRow(run: run, state: state,
                                            isBaseline: store.activeBaselineApproval?.runID == run.id)
                        }
                        .buttonStyle(WorkspaceRowButtonStyle())
                        if run.id != store.runs.last?.id { Divider().padding(.leading, 66) }
                    }
                }
            }
            .workspaceSurface()
        }
    }
}

private struct WorkspaceRunRow: View {
    let run: EvaluationRun
    let state: SuiteCheckState
    let isBaseline: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 18, weight: .light)).foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 40)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(run.startedAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    if isBaseline {
                        Label("Baseline", systemImage: "checkmark.seal")
                            .font(.caption2).foregroundStyle(WorkspaceStyle.success)
                    }
                }
                HStack(spacing: 12) {
                    Label("\(run.passedCount) passed", systemImage: "checkmark.circle")
                        .foregroundStyle(WorkspaceStyle.success)
                    Label("\(run.failedCount) failed", systemImage: "xmark.circle")
                        .foregroundStyle(run.failedCount > 0 ? Color.red : .secondary)
                    if run.errorCount > 0 {
                        Label("\(run.errorCount) errors", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(WorkspaceStyle.warning)
                    }
                }
                .font(.caption)
                Text("\(run.scoredCount) of \(run.results.count) responses scored · \(run.suiteVersion)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            WorkspaceStatusBadge(state: state)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(20).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SuiteCompareView: View {
    @Bindable var store: EvaluationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Compare").font(.title2.bold())
            if let current = store.runs.first,
               let baseline = BaselinePresentation.approvedRun(approval: store.activeBaselineApproval, runs: store.runs),
               baseline.id != current.id {
                RunAnalysisSection(run: current, baselineRuns: [baseline])
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Compare results against your baseline").font(.headline)
                        Text("Approve a completed run from its report, then run the suite again to see what changed.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "arrow.left.arrow.right").font(.title2) }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))
            }
            Divider()
            SuiteExperimentsView(store: store)
        }
    }
}
