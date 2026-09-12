import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: EvaluationStore
    @State private var projectName = ""
    @State private var suiteName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Projects and suites").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Projects").font(.headline)
                    List(selection: Binding(
                        get: { Optional(store.selectedProjectID) },
                        set: { id in
                            guard let id else { return }
                            do { try store.switchProject(id: id) }
                            catch { store.notice = error.localizedDescription }
                        }
                    )) {
                        ForEach(store.projects.filter { !$0.isArchived }) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    HStack {
                        TextField("New project", text: $projectName)
                        Button("Add", systemImage: "plus") {
                            do {
                                _ = try store.createProject(name: projectName.isEmpty ? "New project" : projectName)
                                projectName = ""
                            } catch { store.notice = error.localizedDescription }
                        }
                        .labelStyle(.iconOnly)
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            do { _ = try store.duplicateProject(id: store.selectedProjectID) }
                            catch { store.notice = error.localizedDescription }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                .frame(minWidth: 260)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Suites in \(store.selectedProject.name)").font(.headline)
                    List(selection: Binding(
                        get: { Optional(store.selectedSuiteID) },
                        set: { id in
                            guard let id else { return }
                            do { try store.switchSuite(id: id) }
                            catch { store.notice = error.localizedDescription }
                        }
                    )) {
                        ForEach(store.suiteRecords.filter { !$0.isArchived }) { record in
                            Text(record.name).tag(Optional(record.id))
                        }
                    }
                    HStack {
                        TextField("New suite", text: $suiteName)
                        Button("Add", systemImage: "plus") {
                            do {
                                _ = try store.createSuite(name: suiteName.isEmpty ? "New suite" : suiteName)
                                suiteName = ""
                            } catch { store.notice = error.localizedDescription }
                        }
                        .labelStyle(.iconOnly)
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            do { _ = try store.duplicateSuite(id: store.selectedSuiteID) }
                            catch { store.notice = error.localizedDescription }
                        }
                        .labelStyle(.iconOnly)
                    }
                }
                .frame(minWidth: 300)
            }

            HStack {
                TextField("Rename project", text: Binding(
                    get: { store.selectedProject.name },
                    set: { value in try? store.renameProject(id: store.selectedProjectID, name: value) }
                ))
                TextField("Rename suite", text: Binding(
                    get: { store.selectedSuiteRecord.name },
                    set: { value in try? store.renameSuite(id: store.selectedSuiteID, name: value) }
                ))
                Spacer()
                Menu("Archive", systemImage: "archivebox") {
                    Button("Archive current suite", role: .destructive) {
                        do { try store.archiveSuite(id: store.selectedSuiteID) }
                        catch { store.notice = error.localizedDescription }
                    }
                    Button("Archive current project", role: .destructive) {
                        do { try store.archiveProject(id: store.selectedProjectID) }
                        catch { store.notice = error.localizedDescription }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 720, height: 500)
    }
}

struct JudgeConfigurationSection: View {
    @Bindable var store: EvaluationStore

    var body: some View {
        GroupBox("Independent judge") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Judge", selection: $store.draftSuite.judgeConfiguration.mode) {
                    Text("Same model").tag(EvaluationJudgeMode.sameModel)
                    Text("Independent connection").tag(EvaluationJudgeMode.connection)
                }
                .pickerStyle(.segmented)

                if store.draftSuite.judgeConfiguration.usesExternalConnection {
                    Picker("Connection", selection: $store.draftSuite.judgeConfiguration.connectionID) {
                        Text("Choose a connection").tag(UUID?.none)
                        ForEach(store.judgeConnections) { connection in
                            Text(connection.name).tag(Optional(connection.id))
                        }
                    }

                    if let disclosure = store.externalJudgeDisclosure {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Evidence disclosure", systemImage: "network.badge.shield.half.filled")
                                .font(.headline)
                            Text(disclosure)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            if store.draftSuite.judgeConfiguration.externalEvidenceApprovedAt == nil {
                                Button("Approve this evidence transfer") {
                                    store.approveExternalJudgeDisclosure()
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Label("Approved for this suite", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                    }
                } else {
                    Text("The subject model also scores the response. Use an independent connection when model separation matters.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Include reference images with the judge",
                    isOn: $store.draftSuite.judgeConfiguration.includeReferenceAttachments
                )
                .disabled(!store.draftSuite.judgeConfiguration.usesExternalConnection)
            }
            .padding(8)
        }
        .disabled(store.isRunning || store.isProcessingFiles)
    }
}

struct ReleasePolicySection: View {
    @Bindable var store: EvaluationStore

    var body: some View {
        GroupBox("Release check") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Require this suite for release", isOn: $store.draftSuite.releasePolicy.required)
                if store.draftSuite.releasePolicy.required {
                    Stepper(
                        "Maximum errors: \(store.draftSuite.releasePolicy.maximumErrorCount)",
                        value: $store.draftSuite.releasePolicy.maximumErrorCount,
                        in: 0...100
                    )
                    Toggle("Require an approved baseline", isOn: $store.draftSuite.releasePolicy.requireApprovedBaseline)
                    LabeledContent("Maximum pass-rate regression") {
                        TextField(
                            "0",
                            value: $store.draftSuite.releasePolicy.maximumPassRateRegression,
                            format: .percent.precision(.fractionLength(0...2))
                        )
                        .frame(width: 100)
                    }
                    LabeledContent("Maximum average latency (ms)") {
                        TextField(
                            "No limit",
                            value: $store.draftSuite.releasePolicy.maximumAverageLatencyMilliseconds,
                            format: .number
                        )
                        .frame(width: 120)
                    }
                    Text("Mark critical cases below. Missing, stale, incomplete, or incompatible evidence fails closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(store.draftSuite.cases) { evaluationCase in
                        Toggle(
                            evaluationCase.name.isEmpty ? "Untitled case" : evaluationCase.name,
                            isOn: Binding(
                                get: { store.draftSuite.releasePolicy.criticalCaseIDs.contains(evaluationCase.id) },
                                set: { required in
                                    if required {
                                        if !store.draftSuite.releasePolicy.criticalCaseIDs.contains(evaluationCase.id) {
                                            store.draftSuite.releasePolicy.criticalCaseIDs.append(evaluationCase.id)
                                        }
                                    } else {
                                        store.draftSuite.releasePolicy.criticalCaseIDs.removeAll { $0 == evaluationCase.id }
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .padding(8)
        }
        .disabled(store.isRunning || store.isProcessingFiles)
    }
}

struct SuiteAdvancedView: View {
    @Bindable var store: EvaluationStore
    @State private var experimentName = "Instruction comparison"
    @State private var candidateInstructions = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DisclosureGroup("Subject model", isExpanded: .constant(true)) {
                ModelControlsSection(store: store)
                    .padding(.top, 12)
            }
            DisclosureGroup("Model features") {
                FeatureControlsView(store: store)
                    .padding(.top, 12)
            }
            GroupBox("Controlled instruction experiments") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Freeze the current cases, scoring, and judge configuration, then compare one instruction change in balanced order.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("Experiment name", text: $experimentName)
                    TextEditor(text: $candidateInstructions)
                        .frame(minHeight: 90)
                        .padding(6)
                        .background(.background, in: .rect(cornerRadius: 7))
                        .overlay { RoundedRectangle(cornerRadius: 7).stroke(.separator) }
                    HStack {
                        Button("Create frozen experiment", systemImage: "scale.3d") {
                            do {
                                _ = try store.createInstructionExperiment(
                                    name: experimentName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    candidateInstructions: candidateInstructions
                                )
                                candidateInstructions = ""
                            } catch {
                                store.notice = error.localizedDescription
                            }
                        }
                        .disabled(candidateInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        Text("\(store.suiteLocalState.experiments.count) saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.suiteLocalState.experiments.reversed()) { experiment in
                        ExperimentRow(store: store, experiment: experiment)
                    }
                }
                .padding(8)
            }
        }
    }
}

private struct ExperimentRow: View {
    @Bindable var store: EvaluationStore
    let experiment: EvaluationExperiment

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(experiment.name).font(.headline)
                Spacer()
                if experiment.runIDs.count != 2 {
                    Button("Run") { store.runExperiment(id: experiment.id) }
                        .disabled(store.isRunning)
                } else if let decision = experiment.decision {
                    Text(decision.title).font(.caption).foregroundStyle(.secondary)
                } else {
                    Menu("Record decision") {
                        ForEach(EvaluationExperimentDecision.allCases, id: \.self) { decision in
                            Button(decision.title) {
                                do { try store.decideExperiment(id: experiment.id, decision: decision) }
                                catch { store.notice = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            Text("Current → Candidate · \(experiment.executionOrder.count) balanced sample slots")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(experiment.candidate.instructions)
                .font(.callout)
                .lineLimit(3)
            if experiment.runIDs.count == 2,
               let current = store.run(with: experiment.runIDs[0]),
               let candidate = store.run(with: experiment.runIDs[1]) {
                let summary = EvaluationExperimentAnalyzer.summarize(current: current, candidate: candidate)
                Text("\(summary.improvedCaseIDs.count) improved · \(summary.regressedCaseIDs.count) regressed · \(summary.distinctCaseCoverage) distinct cases · \(summary.explanation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
    }
}

private extension EvaluationExperimentDecision {
    var title: String {
        switch self {
        case .keepCurrent: "Keep current"
        case .adoptCandidate: "Adopt candidate"
        case .collectMoreEvidence: "Collect more evidence"
        case .inconclusive: "Inconclusive"
        }
    }
}

struct CaseImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: EvaluationStore
    @State private var isChoosingFile = false
    @State private var filename = ""
    @State private var data: Data?
    @State private var format = EvaluationCaseImportFormat.csv
    @State private var columns: [String] = []
    @State private var nameColumn: String?
    @State private var promptColumn = ""
    @State private var expectedColumn: String?
    @State private var preview: EvaluationCaseImportPreview?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Import cases").font(.title2.bold())
                    Text("Map UTF-8 CSV or JSONL columns before changing the suite.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose File…") { isChoosingFile = true }
            }

            if data != nil {
                LabeledContent("File", value: filename)
                Picker("Format", selection: $format) {
                    Text("CSV").tag(EvaluationCaseImportFormat.csv)
                    Text("JSON Lines").tag(EvaluationCaseImportFormat.jsonLines)
                }
                .pickerStyle(.segmented)
                .onChange(of: format) { _, _ in prepareColumns() }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow { Text("Name"); optionalColumnPicker(selection: $nameColumn) }
                    GridRow { Text("Prompt"); requiredColumnPicker(selection: $promptColumn) }
                    GridRow { Text("Expected"); optionalColumnPicker(selection: $expectedColumn) }
                }
                .onChange(of: nameColumn) { _, _ in updatePreview() }
                .onChange(of: promptColumn) { _, _ in updatePreview() }
                .onChange(of: expectedColumn) { _, _ in updatePreview() }

                if let preview {
                    if preview.rows.isEmpty {
                        ContentUnavailableView("No importable rows", systemImage: "exclamationmark.tablecells")
                    } else {
                        Table(preview.rows) {
                            TableColumn("Line") { Text($0.sourceLine.formatted()) }.width(45)
                            TableColumn("Name", value: \.name)
                            TableColumn("Prompt", value: \.prompt)
                            TableColumn("Expected", value: \.expected)
                        }
                        .frame(minHeight: 190)
                    }
                    ForEach(preview.issues) { issue in
                        Label(
                            issue.line.map { "Line \($0): \(issue.message)" } ?? issue.message,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Choose a case file",
                    systemImage: "tablecells",
                    description: Text("Nothing is imported until the preview validates.")
                )
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Import \(preview?.rows.count ?? 0) Cases") { importCases() }
                    .buttonStyle(.borderedProminent)
                    .disabled(preview?.canImport != true)
            }
        }
        .padding(22)
        .frame(width: 760, height: 590)
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: [.commaSeparatedText, .json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                data = try Data(contentsOf: url)
                filename = url.lastPathComponent
                format = url.pathExtension.lowercased() == "csv" ? .csv : .jsonLines
                prepareColumns()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func optionalColumnPicker(selection: Binding<String?>) -> some View {
        Picker("Column", selection: selection) {
            Text("Not mapped").tag(String?.none)
            ForEach(columns, id: \.self) { Text($0).tag(Optional($0)) }
        }
        .labelsHidden()
        .frame(width: 240)
    }

    private func requiredColumnPicker(selection: Binding<String>) -> some View {
        Picker("Column", selection: selection) {
            ForEach(columns, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(width: 240)
    }

    private func prepareColumns() {
        guard let data else { return }
        do {
            columns = try EvaluationCaseImporter.columns(in: data, format: format)
            promptColumn = columns.first(where: { $0.localizedCaseInsensitiveCompare("prompt") == .orderedSame })
                ?? columns.first ?? ""
            nameColumn = columns.first(where: { $0.localizedCaseInsensitiveCompare("name") == .orderedSame })
            expectedColumn = columns.first(where: { $0.localizedCaseInsensitiveCompare("expected") == .orderedSame })
            updatePreview()
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func updatePreview() {
        guard let data, !promptColumn.isEmpty else { return }
        do {
            preview = try EvaluationCaseImporter.preview(
                data: data,
                format: format,
                mapping: .init(nameColumn: nameColumn, promptColumn: promptColumn, expectedColumn: expectedColumn)
            )
            errorMessage = nil
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func importCases() {
        guard let data else { return }
        do {
            let remaining = EvaluationStore.maximumCases - store.draftSuite.cases.count
            guard remaining > 0 else { throw EvaluationCaseImportError.tooManyRows(maximum: 0) }
            let imported = try EvaluationCaseImporter.cases(
                data: data,
                format: format,
                mapping: .init(nameColumn: nameColumn, promptColumn: promptColumn, expectedColumn: expectedColumn),
                maximumCases: remaining
            )
            store.draftSuite.cases.append(contentsOf: imported)
            guard store.saveSuite() else { return }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct JudgeConnectionsSettingsView: View {
    @Bindable var store: EvaluationStore
    @State private var selectedID: UUID?
    @State private var draft = EvaluationJudgeConnection(
        id: UUID(), name: "Local judge", kind: .localCompatible,
        baseURL: "http://127.0.0.1:11434/v1", modelID: ""
    )
    @State private var apiKey = ""

    var body: some View {
        HSplitView {
            List(selection: $selectedID) {
                ForEach(store.judgeConnections) { connection in
                    VStack(alignment: .leading) {
                        Text(connection.name)
                        Text(connection.modelID).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(Optional(connection.id))
                }
            }
            .frame(minWidth: 190)
            .onChange(of: selectedID) { _, value in
                if let value, let connection = store.judgeConnections.first(where: { $0.id == value }) {
                    draft = connection
                    apiKey = ""
                }
            }

            Form {
                TextField("Name", text: $draft.name)
                Picker("Kind", selection: $draft.kind) {
                    ForEach(EvaluationJudgeConnectionKind.allCases) { Text($0.title).tag($0) }
                }
                TextField("Base URL", text: $draft.baseURL)
                TextField("Exact model ID", text: $draft.modelID)
                SecureField(draft.requiresAPIKey ? "API key" : "API key (optional)", text: $apiKey)
                Toggle("Strict structured outputs", isOn: $draft.capabilities.structuredOutputs)
                Toggle("Accepts image evidence", isOn: $draft.capabilities.multimodal)
                TextField("Provider order (comma separated)", text: Binding(
                    get: { draft.providerOrder.joined(separator: ", ") },
                    set: { draft.providerOrder = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
                ))
                .disabled(draft.kind != .openRouter)
                Stepper("Timeout: \(Int(draft.requestTimeoutSeconds)) seconds", value: $draft.requestTimeoutSeconds, in: 1...300)
                if let issue = draft.validationIssue {
                    Text(issue).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("New") {
                        selectedID = nil
                        draft = .init(
                            id: UUID(), name: "New judge", kind: .localCompatible,
                            baseURL: "http://127.0.0.1:11434/v1", modelID: ""
                        )
                        apiKey = ""
                    }
                    if selectedID != nil {
                        Button("Delete", role: .destructive) {
                            do { try store.deleteJudgeConnection(id: draft.id); selectedID = nil }
                            catch { store.notice = error.localizedDescription }
                        }
                    }
                    Spacer()
                    if selectedID != nil {
                        Button("Check") { Task { await store.checkJudgeConnection(id: draft.id) } }
                    }
                    Button("Save") {
                        do {
                            try store.saveJudgeConnection(draft, apiKey: apiKey.isEmpty ? nil : apiKey)
                            selectedID = draft.id
                            apiKey = ""
                        } catch { store.notice = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.validationIssue != nil)
                }
                if let checkedAt = draft.lastCheckedAt {
                    Text("Checked \(checkedAt.formatted(date: .abbreviated, time: .shortened)): \(draft.lastCheckMessage ?? "No message")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 410)
        }
        .frame(width: 680, height: 470)
    }
}

struct RunWorkflowPanel: View {
    @Bindable var store: EvaluationStore
    let run: EvaluationRun
    @State private var correctionSample: EvaluationSampleAssessment?
    @State private var reportText: String?

    private var selectedAssessment: EvaluationAssessment? {
        guard let selected = run.selectedAssessmentID else { return run.assessments?.last }
        return run.assessments?.first { $0.id == selected }
    }

    var body: some View {
        GroupBox("Review and approval") {
            VStack(alignment: .leading, spacing: 12) {
                if let assessments = run.assessments, !assessments.isEmpty {
                    Picker("Selected assessment", selection: Binding(
                        get: { run.selectedAssessmentID ?? assessments.last?.id },
                        set: { id in
                            guard let id else { return }
                            do { try store.selectAssessment(runID: run.id, assessmentID: id) }
                            catch { store.notice = error.localizedDescription }
                        }
                    )) {
                        ForEach(assessments) { assessment in
                            Text("\(assessment.judge.displayName) · \(assessment.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .tag(Optional(assessment.id))
                        }
                    }

                    if let assessment = selectedAssessment {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                            GridRow { Text("Origin"); Text(assessment.origin.rawValue) }
                            GridRow { Text("Prompt"); Text(assessment.promptVersion) }
                            GridRow { Text("Judge"); Text(assessment.judge.displayName) }
                            GridRow { Text("Errors"); Text(assessment.errorCount.formatted()) }
                            GridRow {
                                Text("Judge cost")
                                Text(assessment.cost.usd.map { $0.formatted(.currency(code: "USD")) }
                                     ?? assessment.cost.explanation)
                            }
                        }
                        .font(.callout)

                        if !assessment.samples.isEmpty {
                            Menu("Correct a judgment") {
                                ForEach(assessment.samples) { sample in
                                    let name = run.results.first { $0.id == sample.sampleID }?.caseName ?? "Saved sample"
                                    Button(name) { correctionSample = sample }
                                }
                            }
                        }
                    }
                } else {
                    Text("This run has no separately stored assessment. Legacy run scores remain unchanged.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Menu("Reassess saved responses") {
                        ForEach(store.judgeConnections) { connection in
                            Button(connection.name) { store.reassessRun(id: run.id, connectionID: connection.id) }
                        }
                    }
                    .disabled(store.judgeConnections.isEmpty || store.isReassessing)

                    Button("Approve as baseline", systemImage: "checkmark.seal") {
                        do {
                            try store.approveBaseline(runID: run.id, assessmentID: selectedAssessment?.id)
                        } catch { store.notice = error.localizedDescription }
                    }

                    Button("Release report", systemImage: "shippingbox.and.arrow.backward") {
                        reportText = EvaluationReleaseCheckEvaluator.markdown(store.releaseCheckReport(runID: run.id))
                    }
                    Spacer()
                    if store.activeBaselineApproval?.runID == run.id {
                        Label("Approved baseline", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }

                if let reportText {
                    Text(reportText)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(10)
                        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 7))
                }
            }
            .padding(8)
        }
        .sheet(item: $correctionSample) { sample in
            JudgmentCorrectionView(store: store, run: run, assessment: selectedAssessment, sample: sample)
        }
    }
}

private struct JudgmentCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: EvaluationStore
    let run: EvaluationRun
    let assessment: EvaluationAssessment?
    let sample: EvaluationSampleAssessment
    @State private var correctedStatus = EvaluationResultStatus.failed
    @State private var correctedScore: Int? = 2
    @State private var reason = ""
    @State private var reviewer = ""
    @State private var collectAsCheck = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Correct judgment").font(.title2.bold())
            Text("The original \(sample.status.rawValue) judgment and score remain preserved in the run.")
                .foregroundStyle(.secondary)
            Picker("Correct status", selection: $correctedStatus) {
                Text("Passed").tag(EvaluationResultStatus.passed)
                Text("Failed").tag(EvaluationResultStatus.failed)
                Text("Unscored").tag(EvaluationResultStatus.unscored)
            }
            Picker("Correct score", selection: $correctedScore) {
                Text("None").tag(Int?.none)
                ForEach(1...4, id: \.self) { Text($0.formatted()).tag(Optional($0)) }
            }
            TextField("Reviewer (optional)", text: $reviewer)
            TextEditor(text: $reason)
                .frame(minHeight: 100)
                .padding(6)
                .overlay { RoundedRectangle(cornerRadius: 7).stroke(.separator) }
            Toggle("Keep as a known-good judge check", isOn: $collectAsCheck)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save correction") {
                    guard let assessment else { return }
                    do {
                        try store.markJudgmentIncorrect(
                            runID: run.id,
                            assessmentID: assessment.id,
                            sampleID: sample.sampleID,
                            correctedStatus: correctedStatus,
                            correctedScore: correctedScore,
                            reason: reason,
                            reviewer: reviewer.isEmpty ? nil : reviewer,
                            collectAsJudgeCheck: collectAsCheck
                        )
                        dismiss()
                    } catch { store.notice = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 500, height: 420)
    }
}
