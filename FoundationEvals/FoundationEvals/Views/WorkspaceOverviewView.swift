import SwiftUI

struct WorkspaceOverviewView: View {
    @Bindable var store: EvaluationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.selectedProject.name)
                        .font(.largeTitle.bold())
                    Text("See what needs checking before changing code, prompts, or a release baseline.")
                        .foregroundStyle(.secondary)
                }

                if let migrationNotice = store.migrationNotice {
                    Label(migrationNotice, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], spacing: 16) {
                    ForEach(store.suiteRecords.filter { !$0.isArchived }) { record in
                        SuiteOverviewCard(
                            record: record,
                            isSelected: record.id == store.selectedSuiteID,
                            latestRun: record.id == store.selectedSuiteID ? store.runs.first : nil,
                            currentRevision: record.id == store.selectedSuiteID ? store.suiteRevision : nil
                        ) {
                            do {
                                try store.switchSuite(id: record.id)
                                store.selection = .suite
                            } catch {
                                store.notice = error.localizedDescription
                            }
                        }
                    }
                }

                GroupBox("Daily workflow") {
                    HStack(alignment: .top, spacing: 24) {
                        WorkflowStep(number: "1", title: "Change", detail: "Edit cases, expected answers, shared instructions, or app code.")
                        WorkflowStep(number: "2", title: "Check", detail: "Run the suite from the app, MCP, or `foundation-evals check`.")
                        WorkflowStep(number: "3", title: "Review", detail: "Inspect regressions and judge evidence; correct bad judgments.")
                        WorkflowStep(number: "4", title: "Approve", detail: "Explicitly approve one eligible run and assessment as the baseline.")
                    }
                    .padding(8)
                }

                if let repository = store.selectedProject.repository {
                    GroupBox("Repository") {
                        LabeledContent("Linked root", value: repository.rootPath)
                            .textSelection(.enabled)
                        Text("Suite definitions are Git-reviewable. Responses, traces, credentials, and approvals stay local unless explicitly exported.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_000, alignment: .leading)
        }
        .navigationTitle("Project Overview")
    }
}

private struct SuiteOverviewCard: View {
    let record: EvaluationSuiteRecord
    let isSelected: Bool
    let latestRun: EvaluationRun?
    let currentRevision: String?
    let open: () -> Void

    private var isStale: Bool {
        guard let latestRun, let currentRevision else { return true }
        return latestRun.suiteRevision != currentRevision
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: isStale ? "clock.badge.exclamationmark" : "checkmark.circle.fill")
                        .foregroundStyle(isStale ? .orange : .green)
                    Text(record.name).font(.headline)
                    Spacer()
                    if isSelected { Text("Open").font(.caption).foregroundStyle(.secondary) }
                }
                if let latestRun {
                    Text(isStale ? "Definition changed since the latest run" : "Latest run matches the saved definition")
                        .font(.callout)
                    Text("\(latestRun.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(latestRun.passedCount) passed · \(latestRun.failedCount) failed · \(latestRun.errorCount) errors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Needs its first check")
                        .font(.callout)
                    Text("Open the suite to review its cases and run it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)) }
        }
        .buttonStyle(.plain)
    }
}

private struct WorkflowStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SuiteResultsView: View {
    @Bindable var store: EvaluationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results").font(.title2.bold())
            if store.runs.isEmpty {
                ContentUnavailableView("No results yet", systemImage: "chart.bar", description: Text("Run this suite to create immutable local evidence."))
            } else {
                ForEach(store.runs) { run in
                    Button {
                        store.selection = .run(run.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(run.startedAt, format: .dateTime.year().month().day().hour().minute())
                                Text("\(run.passedCount) passed · \(run.failedCount) failed · \(run.errorCount) errors")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if run.suiteRevision != store.suiteRevision {
                                Label("Stale", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
                            }
                        }
                        .padding(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SuiteCompareView: View {
    @Bindable var store: EvaluationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Compare").font(.title2.bold())
            if let current = store.runs.first,
               let baselineApproval = store.activeBaselineApproval,
               let baseline = store.runs.first(where: { $0.id == baselineApproval.runID }),
               baseline.id != current.id {
                RunAnalysisSection(run: current, baselineRuns: [baseline])
            } else {
                ContentUnavailableView(
                    "No approved comparison",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Approve an eligible completed run as the baseline, then run the suite again.")
                )
            }
        }
    }
}
