import SwiftUI
import UniformTypeIdentifiers

private enum RubricTemplate: String, CaseIterable, Identifiable {
    case general
    case factual
    case summary
    case writing

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General answer"
        case .factual: "Grounded answer"
        case .summary: "Summary"
        case .writing: "Writing and tone"
        }
    }

    var requirements: String {
        switch self {
        case .general:
            EvaluationSuite.defaultRubric
        case .factual:
            """
            Every material claim agrees with the supplied reference answer or reference files.
            The response includes all facts needed to answer the prompt.
            The response does not invent unsupported details.
            The response follows every requested format and length constraint.
            """
        case .summary:
            """
            The summary includes every central point from the supplied source.
            The summary contains no claim that is unsupported by the source.
            The summary removes repetition and nonessential detail.
            The summary follows the requested length, format, and tone.
            """
        case .writing:
            """
            The response uses the requested audience, tone, and point of view.
            The response communicates the intended meaning clearly and unambiguously.
            The response is concise and contains no unnecessary repetition.
            The response follows every requested structure and length constraint.
            """
        }
    }
}

struct SuiteEditorView: View {
    @Bindable var store: EvaluationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                instructions
                scoring
                attachments
                cases
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .disabled(store.isRunning || store.isProcessingFiles)
        }
        .navigationTitle("Evaluation Suite")
        .toolbar {
            ToolbarItemGroup {
                if store.isRunning {
                    ProgressView(value: Double(store.completedSamples), total: Double(max(store.totalSamples, 1)))
                        .frame(width: 120)
                    Button("Cancel", role: .cancel) { store.cancelRun() }
                } else {
                    if store.isProcessingFiles {
                        ProgressView("Importing files")
                            .controlSize(.small)
                    }
                    Button("Run", systemImage: "play.fill") { store.startRun() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isProcessingFiles)
                }
            }
        }
        .fileImporter(
            isPresented: $store.isImportingFiles,
            allowedContentTypes: [.text, .json, .commaSeparatedText, .pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): store.importFiles(urls)
            case .failure(let error): store.notice = error.localizedDescription
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Suite name", text: $store.suite.name)
                    .textFieldStyle(.plain)
                    .font(.largeTitle.bold())
                Spacer()
                ModelStatusBadge(status: store.modelStatus)
            }

            HStack {
                LabeledContent("Prompt version") {
                    TextField("v1", text: $store.suite.version)
                        .frame(width: 130)
                }
                Spacer()
                Text("Runs stay on this Mac and export as JSON.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var instructions: some View {
        GroupBox("Model setup") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Instructions")
                    .font(.headline)
                TextEditor(text: $store.suite.instructions)
                    .accessibilityLabel("Instructions")
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .padding(6)
                    .background(.background, in: .rect(cornerRadius: 6))
                Text("A fresh LanguageModelSession uses these instructions for every case and repetition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var scoring: some View {
        GroupBox("Scoring") {
            VStack(alignment: .leading, spacing: 12) {
                Text("How should each response be checked?")
                    .font(.headline)
                Picker("Scoring method", selection: $store.suite.scoringMode) {
                    ForEach(ScoringMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(store.suite.scoringMode.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Stepper("Repetitions: \(store.suite.repetitions)", value: $store.suite.repetitions, in: 1...5)
                }

                if store.suite.scoringMode == .modelJudge {
                    Divider()
                    HStack {
                        Text("Rubric requirements")
                            .font(.headline)
                        Spacer()
                        Menu("Replace with template", systemImage: "wand.and.stars") {
                            ForEach(RubricTemplate.allCases) { template in
                                Button(template.title) {
                                    store.suite.criteria = template.requirements
                                }
                            }
                        }
                    }
                    Text("Write one observable requirement per line. Keep it to four or fewer; the score definitions are added automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $store.suite.criteria)
                        .accessibilityLabel("AI rubric requirements")
                        .font(.body.monospaced())
                        .frame(minHeight: 105)
                        .padding(6)
                        .background(.background, in: .rect(cornerRadius: 6))

                    Label(
                        "\(store.suite.rubricCriteria.count) of 4 recommended requirements",
                        systemImage: (1...4).contains(store.suite.rubricCriteria.count) ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    .foregroundStyle((1...4).contains(store.suite.rubricCriteria.count) ? Color.secondary : Color.orange)

                    rubricScale

                    Label(
                        "Advisory: the subject and judge use the same on-device model. Compare its scores with a small human-reviewed set before using them as a release gate.",
                        systemImage: "person.2"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var rubricScale: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
            GridRow { Text("4").bold(); Text("Every requirement is fully met; no material error.") }
            GridRow { Text("3").bold(); Text("Core requirements are met; only minor issues. Pass.") }
            GridRow { Text("2").bold(); Text("At least one requirement is materially unmet. Fail.") }
            GridRow { Text("1").bold(); Text("Fundamentally wrong, off-task, or violates a key constraint. Fail.") }
        }
        .font(.caption)
        .padding(10)
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var attachments: some View {
        GroupBox("Reference files") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Text, JSON, CSV, PDF, and up to four images")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Files", systemImage: "paperclip") {
                        store.isImportingFiles = true
                    }
                    .disabled(store.isRunning || store.isProcessingFiles)
                }

                if store.suite.attachments.isEmpty {
                    Text("No files attached. Text and PDF content is added to each prompt; images use Foundation Models attachments.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(store.suite.attachments) { attachment in
                        HStack {
                            Image(systemName: attachment.kind == .image ? "photo" : "doc.text")
                                .foregroundStyle(.secondary)
                            Text(attachment.name)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Remove", systemImage: "xmark", role: .destructive) {
                                store.removeAttachment(id: attachment.id)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var cases: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cases")
                    .font(.title2.bold())
                Text("\(store.suite.cases.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Add Case", systemImage: "plus") { store.addCase() }
            }

            ForEach($store.suite.cases) { $evaluationCase in
                EvaluationCaseEditor(
                    evaluationCase: $evaluationCase,
                    scoringMode: store.suite.scoringMode,
                    remove: { store.removeCase(id: evaluationCase.id) }
                )
            }
        }
    }
}

private struct ModelStatusBadge: View {
    var status: ModelStatus

    var body: some View {
        Label(status.label, systemImage: status.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(status.isAvailable ? .green : .orange)
            .help(status.detail)
            .accessibilityLabel("Foundation model status")
            .accessibilityValue(status.label)
    }
}

private struct EvaluationCaseEditor: View {
    @Binding var evaluationCase: EvaluationCase
    var scoringMode: ScoringMode
    var remove: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Case name", text: $evaluationCase.name)
                        .font(.headline)
                        .textFieldStyle(.plain)
                    Spacer()
                    Button("Delete Case", systemImage: "trash", role: .destructive, action: remove)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                }

                Text("Prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $evaluationCase.prompt)
                    .accessibilityLabel("Prompt for \(evaluationCase.name)")
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .padding(6)
                    .background(.background, in: .rect(cornerRadius: 6))

                if scoringMode != .review {
                    Text(scoringMode.expectedLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $evaluationCase.expected)
                        .accessibilityLabel("Expected answer for \(evaluationCase.name)")
                        .frame(minHeight: 58)
                        .padding(6)
                        .background(.background, in: .rect(cornerRadius: 6))
                    Text(scoringMode.expectedHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }
}
