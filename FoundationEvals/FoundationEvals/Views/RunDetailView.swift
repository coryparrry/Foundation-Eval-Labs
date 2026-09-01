import SwiftUI
import UniformTypeIdentifiers

struct RunDetailView: View {
    var run: EvaluationRun
    @State private var exportDocument = JSONDocument()
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summary
                configuration

                ForEach(run.results) { result in
                    resultCard(result)
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .navigationTitle(run.suiteName)
        .toolbar {
            Button("Export JSON", systemImage: "square.and.arrow.up") {
                exportDocument = JSONDocument(run: run)
                isExporting = true
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "\(safeFilename(run.suiteName))-\(run.suiteVersion)-\(run.id.uuidString.prefix(8)).json"
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert("Could not export trace", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.suiteName)
                    .font(.largeTitle.bold())
                if run.cancelled {
                    Text("Cancelled")
                        .foregroundStyle(.orange)
                } else if run.terminationReason == "rateLimited" {
                    Text("Stopped: rate limited")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(run.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                    .foregroundStyle(.secondary)
            }
            Text("\(run.suiteVersion) • \(run.scoringMode.title) • \(run.repetitions) repetition\(run.repetitions == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: "Pass rate (scored)", value: run.passRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—")
            if let averageScore = run.averageScore {
                MetricCard(title: "Average AI score", value: "\(averageScore.formatted(.number.precision(.fractionLength(1)))) / 4")
            }
            MetricCard(title: "Scored", value: "\(run.scoredCount) / \(run.results.count)")
            MetricCard(title: "Passed / Failed", value: "\(run.passedCount) / \(run.failedCount)")
            MetricCard(title: "Errors", value: "\(run.errorCount)")
            MetricCard(title: "Avg subject latency", value: Duration.milliseconds(run.averageDurationMilliseconds).formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))
            MetricCard(title: "Tokens", value: run.totalTokens.formatted())
        }
    }

    private var configuration: some View {
        DisclosureGroup("Run configuration") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledText(label: "Instructions", text: run.instructions.isEmpty ? "None" : run.instructions)
                if run.scoringMode == .modelJudge {
                    LabeledText(label: "AI rubric requirements", text: run.criteria)
                    LabeledText(
                        label: "AI judge",
                        text: "Prompt \(run.judgePromptVersion ?? "legacy") • scores \(run.judgePassingScore ?? EvaluationSuite.judgePassingScore)–4 pass • same on-device model as subject"
                    )
                }
                LabeledText(
                    label: "Environment",
                    text: "\(run.environment.model) • context \(run.environment.modelContextSize) tokens • \(run.environment.operatingSystem) • \(run.environment.locale)"
                )
                if !run.attachments.isEmpty {
                    LabeledText(
                        label: "Reference files",
                        text: run.attachments.map { "\($0.name) (\($0.kind.rawValue), \($0.byteCount) bytes, SHA-256 \($0.sha256))" }.joined(separator: "\n")
                    )
                }
            }
            .padding(.top, 8)
        }
    }

    private func resultCard(_ result: EvaluationSampleResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(result.caseName, systemImage: statusSymbol(result.status))
                        .foregroundStyle(statusColor(result.status))
                        .font(.headline)
                        .accessibilityValue(result.status.rawValue.capitalized)
                    if run.repetitions > 1 {
                        Text("Run \(result.repetition)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let score = result.score {
                        Text("\(score) / 4 • \(score >= (run.judgePassingScore ?? EvaluationSuite.judgePassingScore) ? "Pass" : "Fail")")
                            .font(.headline.monospacedDigit())
                    }
                }

                if let errorMessage = result.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Text(result.errorCategory ?? "error")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    LabeledText(label: "Prompt", text: result.prompt)
                    if let effectivePrompt = result.effectivePrompt, effectivePrompt != result.prompt {
                        LabeledText(label: "Effective model input", text: effectivePrompt)
                    }
                    if !result.expected.isEmpty {
                        LabeledText(label: "Expected / reference answer", text: result.expected)
                    }
                    LabeledText(label: "Response", text: result.response)
                    if let rationale = result.rationale {
                        LabeledText(label: run.scoringMode == .modelJudge ? "Judge rationale" : "Scoring rationale", text: rationale)
                    }
                    if let judgeErrorMessage = result.judgeErrorMessage {
                        Text(judgeErrorMessage)
                            .foregroundStyle(.red)
                        Text("Judge: \(result.judgeErrorCategory ?? "error")")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                Text("\(result.durationMilliseconds.formatted(.number.precision(.fractionLength(0)))) ms • \(result.usage.inputTokens) input • \(result.usage.outputTokens) output • \(result.usage.cachedInputTokens) cached")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let judgeDuration = result.judgeDurationMilliseconds {
                    let judgeUsage = result.judgeUsage ?? EvaluationUsage()
                    Text("Judge: \(judgeDuration.formatted(.number.precision(.fractionLength(0)))) ms • \(judgeUsage.inputTokens) input • \(judgeUsage.outputTokens) output • \(judgeUsage.cachedInputTokens) cached")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .textSelection(.enabled)
        }
    }

    private func statusSymbol(_ status: EvaluationResultStatus) -> String {
        switch status {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .unscored: "circle.dotted"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: EvaluationResultStatus) -> Color {
        switch status {
        case .passed: .green
        case .failed, .error: .red
        case .unscored: .secondary
        }
    }

    private func safeFilename(_ value: String) -> String {
        value.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
    }
}

private struct MetricCard: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 10))
    }
}

private struct LabeledText: View {
    var label: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
