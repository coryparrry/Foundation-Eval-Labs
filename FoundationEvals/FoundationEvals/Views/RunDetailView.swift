import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ResultFilter: String, CaseIterable, Identifiable {
    case all
    case passed
    case failed
    case issues

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .passed: "Passed"
        case .failed: "Failed"
        case .issues: "Issues"
        }
    }

    func includes(_ result: EvaluationSampleResult) -> Bool {
        switch self {
        case .all:
            true
        case .passed:
            result.status == .passed
        case .failed:
            result.status == .failed
        case .issues:
            result.status == .error || result.status == .unscored || result.judgeErrorMessage != nil
        }
    }
}

struct RunDetailView: View {
    let run: EvaluationRun
    let baselineRuns: [EvaluationRun]
    @State private var exportDocument = JSONDocument()
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                RunOverviewHeader(run: run)
                RunSummaryGrid(run: run)
                RunAnalysisSection(run: run, baselineRuns: baselineRuns)
                RunConfigurationSection(run: run)
                ResultsSection(run: run)
            }
            .padding(28)
            .frame(maxWidth: 1_100, alignment: .leading)
        }
        .navigationTitle("Run Results")
        .toolbar {
            Button("Export Run as JSON", systemImage: "square.and.arrow.up") {
                do {
                    exportDocument = try JSONDocument(run: run)
                    isExporting = true
                } catch {
                    exportError = error.localizedDescription
                }
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
        .alert(
            "Could not export run",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func safeFilename(_ value: String) -> String {
        value.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
    }
}

private struct RunOverviewHeader: View {
    let run: EvaluationRun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EVALUATION RUN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(run.suiteName)
                    .font(.largeTitle.bold())
                RunStatusBadge(run: run)
                Spacer()
            }

            HStack(spacing: 10) {
                Text(run.suiteVersion)
                Text("·")
                Text(run.scoringMode.title)
                Text("·")
                Text(run.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                Text("·")
                Text(run.totalDuration.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct RunStatusBadge: View {
    let run: EvaluationRun

    private var title: LocalizedStringResource {
        if run.cancelled { return "Cancelled" }
        if run.stoppedEarly { return "Stopped early" }
        if run.errorCount > 0 { return "Completed with issues" }
        if run.failedCount > 0 { return "Completed with failures" }
        return "Completed"
    }

    private var symbol: String {
        if run.cancelled { return "stop.circle.fill" }
        if run.stoppedEarly || run.errorCount > 0 { return "exclamationmark.circle.fill" }
        if run.failedCount > 0 { return "xmark.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var color: Color {
        if run.cancelled || run.stoppedEarly { return .orange }
        return run.errorCount > 0 || run.failedCount > 0 ? .red : .green
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.09), in: .capsule)
    }
}

private struct RunSummaryGrid: View {
    let run: EvaluationRun

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(
                title: "Scored pass rate",
                value: run.passRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                symbol: "chart.bar.fill"
            )
            MetricCard(
                title: "Completed",
                value: "\(run.results.count) / \(run.plannedResultCount)",
                symbol: "checklist"
            )
            MetricCard(title: "Passed", value: run.passedCount.formatted(), symbol: "checkmark.circle")
            MetricCard(title: "Failed", value: run.failedCount.formatted(), symbol: "xmark.circle")
            MetricCard(title: "Issues", value: run.errorCount.formatted(), symbol: "exclamationmark.triangle")
            if let averageScore = run.averageScore {
                MetricCard(
                    title: "Average AI score",
                    value: "\(averageScore.formatted(.number.precision(.fractionLength(1)))) / 4",
                    symbol: "sparkles"
                )
            }
            MetricCard(
                title: "Average latency",
                value: Duration.milliseconds(run.averageDurationMilliseconds)
                    .formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)),
                symbol: "timer"
            )
            MetricCard(title: "Tokens", value: run.totalTokens.formatted(), symbol: "number")
        }
        .padding(16)
        .background(.thinMaterial, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12))
        }
    }
}

private struct RunConfigurationSection: View {
    let run: EvaluationRun

    var body: some View {
        DisclosureGroup("Run configuration") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledText(label: "Instructions", text: run.instructions.isEmpty ? "None" : run.instructions)
                if let execution = run.execution {
                    let configuration = execution.configuration
                    LabeledText(
                        label: "Model provider",
                        text: "\(execution.modelDisplayName) · \(configuration.provider.title)"
                    )
                    LabeledText(
                        label: "Reasoning and generation",
                        text: "Reasoning \(configuration.reasoningLevel.title) · \(configuration.samplingSummary) · temperature \(configuration.temperatureEnabled ? configuration.temperature.formatted(.number.precision(.fractionLength(2))) : "automatic") · maximum \(configuration.maximumResponseTokens) response tokens"
                    )
                    LabeledText(
                        label: "Context and references",
                        text: contextSummary(execution: execution)
                    )
                    LabeledText(
                        label: "Execution contract",
                        text: "\(execution.behaviorVersion) · capabilities: \(execution.capabilities.joined(separator: ", ")) · tools: \(execution.toolNames.isEmpty ? "none" : execution.toolNames.joined(separator: ", "))"
                    )
                    if let features = execution.features {
                        FeatureConfigurationSummary(configuration: features)
                    }
                }
                if run.scoringMode == .modelJudge {
                    LabeledText(label: "AI rubric requirements", text: run.criteria)
                    LabeledText(
                        label: "AI judge",
                        text: "Prompt \(run.judgePromptVersion ?? "legacy") · scores \(run.judgePassingScore ?? EvaluationSuite.judgePassingScore)–4 pass · selected provider with fixed greedy decoding and tools off"
                    )
                }
                LabeledText(
                    label: "Environment",
                    text: "\(run.environment.model) · \(run.environment.modelContextSize) token context · \(run.environment.operatingSystem) · \(run.environment.locale)"
                )
                if !run.attachments.isEmpty {
                    LabeledText(
                        label: "Shared reference files",
                        text: run.attachments.map {
                            "\($0.name) (\($0.kind.rawValue), \($0.byteCount) bytes, SHA-256 \($0.sha256))"
                        }.joined(separator: "\n")
                    )
                }
            }
            .padding(.top, 12)
        }
        .font(.headline)
        .padding(18)
        .background(.thinMaterial, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.14))
        }
    }

    private func contextSummary(execution: EvaluationExecutionTrace) -> String {
        let configuration = execution.configuration
        let requested = configuration.maximumInputTokens.map { "\($0) tokens" } ?? "automatic"
        let effective = execution.effectiveInputTokenLimit.map { " · effective \($0) tokens" } ?? ""
        let toolReserve = execution.reservedToolOutputTokens.flatMap { $0 > 0 ? " · tool reserve \($0) tokens" : nil } ?? ""
        let judgeReserve = execution.reservedJudgeOverheadTokens.flatMap { $0 > 0 ? " · judge reserve \($0) tokens" : nil } ?? ""
        let counting = execution.inputTokenCountingMethod.map { " · \($0)" } ?? ""
        return "Requested \(requested)\(effective)\(toolReserve)\(judgeReserve)\(counting) · \(configuration.contextPolicy.title) · \(configuration.referenceMode.title)"
    }
}

private struct ResultsSection: View {
    let run: EvaluationRun
    @State private var filter = ResultFilter.all
    @State private var searchText = ""
    @State private var selectedResultID: UUID?

    private var results: [EvaluationSampleResult] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return run.results.filter { result in
            filter.includes(result)
                && (query.isEmpty
                    || result.caseName.localizedCaseInsensitiveContains(query)
                    || result.prompt.localizedCaseInsensitiveContains(query)
                    || result.response.localizedCaseInsensitiveContains(query)
                    || result.reasoningText?.localizedCaseInsensitiveContains(query) == true
                    || result.judgeReasoningText?.localizedCaseInsensitiveContains(query) == true
                    || result.errorMessage?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private var selectedResult: EvaluationSampleResult? {
        guard let selectedResultID else { return results.first }
        return results.first(where: { $0.id == selectedResultID }) ?? results.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Results")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("\(results.count)")
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Picker("Result filter", selection: $filter) {
                    ForEach(ResultFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 390)

                Spacer()

                TextField("Search case, prompt, or response", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 290)
            }

            if results.isEmpty {
                ContentUnavailableView(
                    "No Matching Results",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Change the filter or search text to see more results.")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    List(results, selection: $selectedResultID) { result in
                        ResultListRow(result: result, repetitions: run.repetitions)
                            .tag(result.id)
                    }
                    .listStyle(.inset)
                    .frame(width: 290)
                    .accessibilityIdentifier("Result list")

                    if let selectedResult {
                        ScrollView {
                            ResultDetail(
                                result: selectedResult,
                                scoringMode: run.scoringMode,
                                repetitions: run.repetitions,
                                passingScore: run.judgePassingScore ?? EvaluationSuite.judgePassingScore
                            )
                            .id(selectedResult.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 8)
                            .accessibilityIdentifier("Result detail")
                        }
                    }
                }
                .frame(height: 560)
            }
        }
        .onAppear { selectFirstResultIfNeeded() }
        .onChange(of: results.map(\.id)) { _, _ in
            selectFirstResultIfNeeded()
        }
    }

    private func selectFirstResultIfNeeded() {
        if selectedResultID.flatMap({ id in results.firstIndex(where: { $0.id == id }) }) == nil {
            selectedResultID = results.first?.id
        }
    }
}

private struct ResultListRow: View {
    let result: EvaluationSampleResult
    let repetitions: Int

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.caseName)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if repetitions > 1 {
                        Text("Repetition \(result.repetition)")
                    }
                    Text(statusTitle)
                    if let score = result.score {
                        Text("\(score) / 4")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch result.status {
        case .passed: "Passed"
        case .failed: "Failed"
        case .unscored: "Unscored"
        case .error: "Error"
        }
    }

    private var statusSymbol: String {
        switch result.status {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .unscored: "circle.dotted"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .passed: .green
        case .failed, .error: .red
        case .unscored: .secondary
        }
    }
}

private struct ResultDetail: View {
    let result: EvaluationSampleResult
    let scoringMode: ScoringMode
    let repetitions: Int
    let passingScore: Int
    @State private var hasCopiedResponse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ResultCardHeader(
                result: result,
                repetitions: repetitions,
                passingScore: passingScore
            )

            Divider()

            if let errorMessage = result.errorMessage {
                ErrorBanner(
                    title: "Response failed",
                    message: errorMessage,
                    category: result.errorCategory
                )
            }

            LabeledText(label: "Prompt", text: result.prompt)

            if let effectivePrompt = result.effectivePrompt, effectivePrompt != result.prompt {
                LabeledText(label: "Effective model input", text: effectivePrompt)
            }

            if !result.expected.isEmpty {
                LabeledText(label: "Expected or reference answer", text: result.expected)
            }

            ResponseTextBlock(
                response: result.response,
                hasCopied: hasCopiedResponse,
                copy: copyResponse
            )

            if result.reasoningText != nil || result.usage.reasoningTokens > 0 {
                ReasoningTraceSection(
                    title: "Response reasoning",
                    text: result.reasoningText,
                    tokenCount: result.usage.reasoningTokens
                )
            }

            if let rationale = result.rationale {
                LabeledText(
                    label: scoringMode == .modelJudge ? "AI judge rationale" : "Scoring rationale",
                    text: rationale
                )
            }

            if result.judgeReasoningText != nil || (result.judgeUsage?.reasoningTokens ?? 0) > 0 {
                ReasoningTraceSection(
                    title: "AI judge reasoning",
                    text: result.judgeReasoningText,
                    tokenCount: result.judgeUsage?.reasoningTokens ?? 0
                )
            }

            if let judgeErrorMessage = result.judgeErrorMessage {
                ErrorBanner(
                    title: "AI scoring failed",
                    message: judgeErrorMessage,
                    category: result.judgeErrorCategory
                )
            }

            SampleTraceSection(result: result)
            if let trace = result.featureTrace { FeatureTraceSection(trace: trace) }
        }
        .textSelection(.enabled)
    }

    private func copyResponse() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.response, forType: .string)
        hasCopiedResponse = true
    }
}

private struct ReasoningTraceSection: View {
    let title: LocalizedStringResource
    let text: String?
    let tokenCount: Int

    var body: some View {
        DisclosureGroup(title) {
            Text(text ?? "The model used \(tokenCount) reasoning tokens, but did not expose readable reasoning for this response.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .font(.callout)
    }
}

private struct ResultCardHeader: View {
    let result: EvaluationSampleResult
    let repetitions: Int
    let passingScore: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.caseName)
                    .font(.headline)
                if repetitions > 1 {
                    Text("Repetition \(result.repetition) of \(repetitions)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(statusTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.09), in: .capsule)

            if let score = result.score {
                Text("\(score) / 4")
                    .font(.headline.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch result.status {
        case .passed: "Passed"
        case .failed: "Failed"
        case .unscored: "Unscored"
        case .error: "Error"
        }
    }

    private var statusSymbol: String {
        switch result.status {
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .unscored: "circle.dotted"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .passed: .green
        case .failed, .error: .red
        case .unscored: .secondary
        }
    }
}

private struct ResponseTextBlock: View {
    let response: String
    let hasCopied: Bool
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Response")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !response.isEmpty {
                    Button(
                        hasCopied ? "Copied" : "Copy Response",
                        systemImage: hasCopied ? "checkmark" : "doc.on.doc",
                        action: copy
                    )
                    .buttonStyle(.borderless)
                }
            }
            Text(response.isEmpty ? "No response was captured." : response)
                .foregroundStyle(response.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ErrorBanner: View {
    let title: LocalizedStringResource
    let message: String
    let category: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(message)
                if let category {
                    Text(category)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: .rect(cornerRadius: 9))
    }
}

private struct MetricCard: View {
    let title: LocalizedStringResource
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct LabeledText: View {
    let label: LocalizedStringResource
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
