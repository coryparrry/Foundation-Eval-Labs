import CryptoKit
import Foundation
import FoundationModels
import ImageIO
import Observation
import PDFKit
import Security
import UniformTypeIdentifiers

@MainActor
@Observable
final class EvaluationStore {
    nonisolated static let maximumCases = 100
    nonisolated static let maximumPlannedSamples = 100
    nonisolated static let maximumAttachments = 20
    nonisolated static let maximumImages = 4
    nonisolated static let maximumFieldCharacters = 32_000
    nonisolated static let maximumCombinedSuiteCharacters = 256_000
    nonisolated static let maximumRubricRequirementCharacters = 4_000
    nonisolated static let maximumExtractedTextCharacters = 16_000
    nonisolated static let maximumTextFileBytes = 5_000_000
    nonisolated static let maximumImageBytes = 10_000_000

    private(set) var suite: EvaluationSuite
    var draftSuite: EvaluationSuite
    var runs: [EvaluationRun]
    var selection = SidebarSelection.suite
    var isRunning = false
    var completedSamples = 0
    var totalSamples = 0
    var notice: String?
    var isImportingFiles = false
    var isProcessingFiles = false
    private(set) var activeRun: EvaluationActiveRun?

    private let runner = EvaluationRunner()
    private let supportDirectory: URL
    private let attachmentsDirectory: URL
    private let runsDirectory: URL
    private let activeRunURL: URL
    private var runTask: Task<Void, Never>?
    private var activeRunSuite: EvaluationSuite?
    private var activeRunResults: [EvaluationSampleResult] = []

    init(supportDirectory customSupportDirectory: URL? = nil) {
        let base = customSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "FoundationEvals", directoryHint: .isDirectory)
        supportDirectory = base
        attachmentsDirectory = base.appending(path: "Attachments", directoryHint: .isDirectory)
        runsDirectory = base.appending(path: "Runs", directoryHint: .isDirectory)
        activeRunURL = base.appending(path: "active-run.json")

        var startupNotice: String?
        do {
            try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
        } catch {
            startupNotice = "Could not create local storage: \(error.localizedDescription)"
        }

        let loadedSuite = Self.loadSuite(from: base)
        var initialSuite = loadedSuite.suite ?? EvaluationSuite()
        let migratedRubric = initialSuite.criteria == EvaluationSuite.legacyDefaultCriteria
        let migratedProvider = initialSuite.modelConfiguration.provider != .onDevice
        if migratedRubric {
            initialSuite.criteria = EvaluationSuite.defaultRubric
            if initialSuite.cases.count == 1,
               initialSuite.cases[0].prompt == "Explain why the sky appears blue in two sentences.",
               initialSuite.cases[0].expected.isEmpty {
                initialSuite.cases[0].expected = EvaluationSuite().cases[0].expected
            }
        }
        if migratedProvider {
            initialSuite.modelConfiguration.provider = .onDevice
            initialSuite.modelConfiguration.reasoningLevel = .automatic
        }
        var loadedRuns = Self.loadRuns(from: runsDirectory)
        let recovery = Self.recoverInterruptedRun(
            from: activeRunURL,
            runsDirectory: runsDirectory,
            existingRuns: loadedRuns.runs
        )
        if let recoveredRun = recovery.run {
            loadedRuns.runs.append(recoveredRun)
            loadedRuns.runs.sort { $0.startedAt > $1.startedAt }
        }
        let initialNotice = [startupNotice, loadedSuite.notice, loadedRuns.notice, recovery.notice]
            .compactMap { $0 }
            .joined(separator: "\n")
        suite = initialSuite
        draftSuite = initialSuite
        runs = loadedRuns.runs
        activeRun = nil
        activeRunSuite = nil
        activeRunResults = []
        notice = initialNotice.isEmpty ? nil : initialNotice
        if migratedRubric || migratedProvider { saveSuite() }
    }

    var modelStatus: ModelStatus {
        modelStatus(for: draftSuite)
    }

    func modelStatus(for candidate: EvaluationSuite) -> ModelStatus {
        switch candidate.modelConfiguration.provider {
        case .onDevice:
            return switch SystemLanguageModel.default.availability {
            case .available:
                ModelStatus(isAvailable: true, label: "On-device model ready", detail: "Prompts and reference-tool lookups stay on this Mac.")
            case .unavailable(.deviceNotEligible):
                ModelStatus(isAvailable: false, label: "Device not eligible", detail: "This Mac does not support Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                ModelStatus(isAvailable: false, label: "Apple Intelligence off", detail: "Enable Apple Intelligence in System Settings.")
            case .unavailable(.modelNotReady):
                ModelStatus(isAvailable: false, label: "Model not ready", detail: "The model may still be downloading.")
            case .unavailable:
                ModelStatus(isAvailable: false, label: "Model unavailable", detail: "The model is unavailable for an unknown reason.")
            }
        case .privateCloudCompute:
            guard Self.hasAuthorizedPrivateCloudComputeSignature else {
                return ModelStatus(
                    isAvailable: false,
                    label: "Approved cloud signature required",
                    detail: "Sign a Release build with a non-ad-hoc Apple Development or Distribution identity approved for the managed Private Cloud Compute entitlement."
                )
            }
            let model = PrivateCloudComputeLanguageModel()
            if model.quotaUsage.isLimitReached {
                return ModelStatus(
                    isAvailable: false,
                    label: "Cloud quota reached",
                    detail: model.quotaUsage.resetDate.map { "Quota resets \($0.formatted(date: .abbreviated, time: .shortened))." }
                        ?? "Private Cloud Compute quota is currently exhausted."
                )
            }
            switch model.availability {
            case .available:
                return ModelStatus(
                    isAvailable: true,
                    label: "Cloud model ready",
                    detail: "Requests use Apple's Private Cloud Compute over the network and consume quota."
                )
            case .unavailable(.deviceNotEligible):
                return ModelStatus(isAvailable: false, label: "Device not eligible", detail: "This Mac is not eligible for Private Cloud Compute model requests.")
            case .unavailable(.systemNotReady):
                return ModelStatus(isAvailable: false, label: "Cloud model not ready", detail: "Check the network connection and Private Cloud Compute entitlement.")
            case .unavailable:
                return ModelStatus(isAvailable: false, label: "Cloud model unavailable", detail: "Private Cloud Compute is unavailable for an unknown reason.")
            }
        }
    }

    var selectedModelCapabilities: LanguageModelCapabilities {
        selectedModelCapabilities(for: draftSuite)
    }

    func selectedModelCapabilities(for candidate: EvaluationSuite) -> LanguageModelCapabilities {
        switch candidate.modelConfiguration.provider {
        case .onDevice: SystemLanguageModel.default.capabilities
        case .privateCloudCompute: PrivateCloudComputeLanguageModel().capabilities
        }
    }

    var plannedSampleCount: Int {
        draftSuite.cases.count * draftSuite.repetitions
    }

    var plannedRequestCount: Int {
        plannedSampleCount * (draftSuite.scoringMode == .modelJudge ? 2 : 1)
    }

    var plannedToolCallLimit: Int {
        let allowances = (draftSuite.modelConfiguration.referenceMode == .lookupTool ? 1 : 0)
            + (draftSuite.features.tools.isEmpty ? 0 : 1)
        return plannedSampleCount * draftSuite.modelConfiguration.maximumToolCalls * allowances
    }

    var runBlocker: String? {
        validationIssue(for: draftSuite)
    }

    var suiteRevision: String {
        (try? currentSuiteRevision()) ?? ""
    }

    func currentSuiteRevision() throws -> String {
        try Self.revision(for: suite)
    }

    func addCase() {
        guard draftSuite.cases.count < Self.maximumCases,
              draftSuite.cases.count < Self.maximumPlannedSamples / max(draftSuite.repetitions, 1) else {
            notice = "This suite has reached its planned-sample limit."
            return
        }
        draftSuite.cases.append(
            EvaluationCase(
                name: "Case \(draftSuite.cases.count + 1)",
                prompt: "",
                expected: ""
            )
        )
        _ = saveSuite()
    }

    func duplicateCase(id: UUID) {
        guard draftSuite.cases.count < Self.maximumCases,
              draftSuite.cases.count < Self.maximumPlannedSamples / max(draftSuite.repetitions, 1) else {
            notice = "This suite has reached its planned-sample limit."
            return
        }
        guard let index = draftSuite.cases.firstIndex(where: { $0.id == id }) else { return }
        var copy = draftSuite.cases[index]
        copy.id = UUID()
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Copied case"
            : "\(copy.name) copy"
        draftSuite.cases.insert(copy, at: index + 1)
        _ = saveSuite()
    }

    func removeCase(id: UUID) {
        guard draftSuite.cases.count > 1 else {
            notice = "An evaluation suite needs at least one case."
            return
        }
        draftSuite.cases.removeAll { $0.id == id }
        _ = saveSuite()
    }

    func replaceSuite(
        _ replacement: EvaluationSuite,
        expectedRevision: String,
        confirmDeletes: Bool
    ) throws -> String {
        var candidate = replacement
        candidate.id = suite.id
        candidate.attachments = suite.attachments
        let candidateRevision = try Self.revision(for: candidate)
        let currentRevision = try currentSuiteRevision()
        if candidateRevision == currentRevision { return candidateRevision }

        try requireIdle()
        try requireRevision(expectedRevision)
        let removedCases = Set(suite.cases.map(\.id)).subtracting(replacement.cases.map(\.id))
        guard removedCases.isEmpty || confirmDeletes else {
            throw EvaluationStoreError.deletionConfirmationRequired
        }
        if let issue = validationIssue(for: candidate, includeModelReadiness: false) {
            throw EvaluationStoreError.invalidSuite(issue)
        }
        try commitSuite(candidate)
        draftSuite = candidate
        return try currentSuiteRevision()
    }

    func deleteRun(id: UUID) {
        do {
            _ = try deleteRunDurably(id: id)
        } catch {
            notice = "Could not delete the saved run: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func deleteRunDurably(id: UUID) throws -> Bool {
        if activeRun?.id == id { throw EvaluationStoreError.runBusy }
        guard runs.contains(where: { $0.id == id }) else { return false }
        do {
            try FileManager.default.removeItem(at: runsDirectory.appending(path: "\(id.uuidString).json"))
        } catch CocoaError.fileNoSuchFile {
            // Missing backing data is already the requested durable state.
        } catch {
            throw EvaluationStoreError.persistence(error.localizedDescription)
        }

        runs.removeAll { $0.id == id }
        if selection == .run(id) { selection = .suite }
        return true
    }

    func importFiles(_ urls: [URL]) {
        guard !isRunning, !isProcessingFiles else {
            notice = "Wait for the current operation to finish before changing files."
            return
        }
        isProcessingFiles = true
        let expectedRevision = suiteRevision

        Task {
            defer { isProcessingFiles = false }
            do {
                let inputs = try await Task.detached(priority: .userInitiated) {
                    try urls.map { url -> AttachmentInput in
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        let type = UTType(filenameExtension: url.pathExtension)
                        let isImage = type?.conforms(to: .image) == true
                        guard let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                            throw ImportError.unknownFileSize
                        }
                        guard byteCount <= (isImage ? Self.maximumImageBytes : Self.maximumTextFileBytes) else {
                            throw isImage ? ImportError.imageTooLarge : ImportError.fileTooLarge
                        }
                        let data = try Data(contentsOf: url, options: .mappedIfSafe)
                        return AttachmentInput(
                            id: UUID(),
                            name: url.lastPathComponent,
                            mediaType: type?.preferredMIMEType ?? "application/octet-stream",
                            data: data
                        )
                    }
                }.value
                try await importAttachments(inputs, expectedRevision: expectedRevision)
            } catch {
                notice = "Could not import files: \(error.localizedDescription)"
            }
        }
    }

    func importAttachment(
        id: UUID,
        name: String,
        mediaType: String,
        data: Data,
        expectedRevision: String
    ) async throws -> EvaluationAttachmentImportResult {
        if let existing = suite.attachments.first(where: { $0.id == id }) {
            let digest = Self.sha256(data)
            guard existing.sha256 == digest, existing.name == name else {
                throw EvaluationStoreError.resourceConflict("Attachment ID already exists with different content.")
            }
            return EvaluationAttachmentImportResult(
                attachment: existing,
                truncated: existing.text?.hasSuffix("\n[File truncated during import.]") == true,
                duplicate: true,
                revision: try currentSuiteRevision()
            )
        }
        try requireIdle()
        try requireRevision(expectedRevision)

        let prepared = try await Task.detached(priority: .userInitiated) {
            try Self.prepareAttachment(id: id, name: name, mediaType: mediaType, data: data)
        }.value

        try requireIdle()
        try requireRevision(expectedRevision)
        return try commitPreparedAttachments([prepared]).first!
    }

    func removeAttachment(id: UUID) {
        do {
            _ = try removeAttachment(id: id, expectedRevision: suiteRevision)
        } catch {
            notice = "Could not remove the imported file: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func removeAttachment(id: UUID, expectedRevision: String) throws -> Bool {
        try requireIdle()
        guard let attachment = suite.attachments.first(where: { $0.id == id }) else { return false }
        try requireRevision(expectedRevision)

        var candidate = suite
        candidate.attachments.removeAll { $0.id == id }
        try commitSuite(candidate)
        draftSuite.attachments.removeAll { $0.id == id }

        if let storedFilename = attachment.storedFilename {
            do {
                try FileManager.default.removeItem(at: attachmentsDirectory.appending(path: storedFilename))
            } catch CocoaError.fileNoSuchFile {
                // Missing content is already unreferenced.
            } catch {
                notice = "The attachment was removed, but its private file could not be cleaned up: \(error.localizedDescription)"
            }
        }
        return true
    }

    @discardableResult
    func saveSuite() -> Bool {
        do {
            try commitSuite(draftSuite)
            return true
        } catch EvaluationStoreError.invalidSuite {
            return false
        } catch {
            notice = "Could not save the suite: \(error.localizedDescription)"
            return false
        }
    }

    func startRun() {
        guard saveSuite() else { return }
        do {
            _ = try startRun(id: UUID(), expectedRevision: suiteRevision)
        } catch {
            notice = error.localizedDescription
        }
    }

    func cancelRun() {
        guard let id = activeRun?.id else { return }
        do {
            _ = try cancelRun(id: id)
        } catch {
            notice = error.localizedDescription
        }
    }

    func run(with id: UUID) -> EvaluationRun? {
        runs.first { $0.id == id }
    }

    @discardableResult
    func startRun(id: UUID, expectedRevision: String) throws -> EvaluationRunOperation {
        if let existing = runStatus(id: id) {
            guard existing.suiteRevision == expectedRevision else {
                throw EvaluationStoreError.resourceConflict("Run ID already belongs to another suite revision.")
            }
            return existing
        }
        try requireIdle()
        try requireRevision(expectedRevision)
        guard let issue = validationIssue(for: suite) else {
            let suiteSnapshot = suite
            let startedAt = Date()
            let total = suiteSnapshot.cases.count * suiteSnapshot.repetitions
            let active = EvaluationActiveRun(
                id: id,
                suiteRevision: expectedRevision,
                startedAt: startedAt,
                completedSamples: 0,
                totalSamples: total,
                cancellationRequested: false
            )
            let record = ActiveRunRecord(summary: active, suite: suiteSnapshot, results: [])

            try commitSuite(suiteSnapshot)
            try persistActiveRun(record)
            activeRun = active
            activeRunSuite = suiteSnapshot
            activeRunResults = []
            isRunning = true
            completedSamples = 0
            totalSamples = total
            let images = imageInputs(for: suiteSnapshot)

            runTask = Task { [weak self] in
                guard let self else { return }
                let run = await runner.run(
                    id: id,
                    suiteRevision: expectedRevision,
                    startedAt: startedAt,
                    suite: suiteSnapshot,
                    images: images
                ) { [weak self] result, completed, total in
                    await self?.updateProgress(runID: id, result: result, completed: completed, total: total)
                }
                finish(run)
            }
            return operation(for: active)
        }
        throw EvaluationStoreError.invalidSuite(issue)
    }

    func runStatus(id: UUID) -> EvaluationRunOperation? {
        if let activeRun, activeRun.id == id { return operation(for: activeRun) }
        guard let run = run(with: id) else { return nil }
        let phase: EvaluationRunPhase
        if run.cancelled {
            phase = .cancelled
        } else if run.terminationReason == "interrupted" {
            phase = .interrupted
        } else if run.stoppedEarly {
            phase = .stopped
        } else {
            phase = .completed
        }
        return EvaluationRunOperation(
            id: run.id,
            suiteRevision: run.suiteRevision,
            phase: phase,
            completedSamples: run.results.count,
            totalSamples: run.plannedResultCount,
            startedAt: run.startedAt,
            completedAt: run.completedAt
        )
    }

    @discardableResult
    func cancelRun(id: UUID) throws -> EvaluationRunOperation {
        if let finished = runStatus(id: id), finished.phase != .running, finished.phase != .cancellationRequested {
            return finished
        }
        guard var active = activeRun, active.id == id else {
            throw EvaluationStoreError.resourceNotFound("Run")
        }
        if !active.cancellationRequested {
            active.cancellationRequested = true
            guard let activeRunSuite else {
                throw EvaluationStoreError.persistence("The active run snapshot is unavailable.")
            }
            try persistActiveRun(ActiveRunRecord(summary: active, suite: activeRunSuite, results: activeRunResults))
            activeRun = active
            runTask?.cancel()
        }
        return operation(for: active)
    }

    func canonicalRunData(id: UUID) throws -> Data {
        guard let run = run(with: id) else { throw EvaluationStoreError.resourceNotFound("Run") }
        return try CanonicalJSON.data(for: run)
    }

    func partialResults(runID: UUID) -> [EvaluationSampleResult] {
        activeRun?.id == runID ? activeRunResults : []
    }

    func attachmentData(id: UUID) throws -> (attachment: EvaluationAttachment, data: Data) {
        guard let attachment = suite.attachments.first(where: { $0.id == id }) else {
            throw EvaluationStoreError.resourceNotFound("Attachment")
        }
        if let text = attachment.text { return (attachment, Data(text.utf8)) }
        guard let storedFilename = attachment.storedFilename else {
            throw EvaluationStoreError.persistence("The attachment has no stored content.")
        }
        do {
            return (attachment, try Data(contentsOf: attachmentsDirectory.appending(path: storedFilename)))
        } catch {
            throw EvaluationStoreError.persistence(error.localizedDescription)
        }
    }

    private func finish(_ run: EvaluationRun) {
        guard activeRun?.id == run.id else { return }
        do {
            try persistRun(run)
            runs.removeAll { $0.id == run.id }
            runs.insert(run, at: 0)
            selection = .run(run.id)
            try? FileManager.default.removeItem(at: activeRunURL)
        } catch {
            notice = "The run finished, but its trace could not be saved: \(error.localizedDescription)"
            activeRunResults = run.results
            if var active = activeRun {
                active.completedSamples = run.results.count
                activeRun = active
            }
            isRunning = false
            runTask = nil
            return
        }
        activeRun = nil
        activeRunSuite = nil
        activeRunResults = []
        isRunning = false
        runTask = nil
    }

    private func updateProgress(
        runID: UUID,
        result: EvaluationSampleResult,
        completed: Int,
        total: Int
    ) {
        guard var active = activeRun, active.id == runID else { return }
        activeRunResults.append(result)
        completedSamples = completed
        totalSamples = total
        active.completedSamples = completed
        active.totalSamples = total
        activeRun = active
        if let activeRunSuite {
            do {
                try persistActiveRun(
                    ActiveRunRecord(summary: active, suite: activeRunSuite, results: activeRunResults)
                )
            } catch {
                notice = "Run progress could not be checkpointed: \(error.localizedDescription)"
            }
        }
    }

    func validationIssue(
        for candidate: EvaluationSuite,
        includeModelReadiness: Bool = true
    ) -> String? {
        let configuration = candidate.modelConfiguration
        if let issue = candidate.features.validationIssue { return issue }
        if candidate.features.tools.contains(where: { $0.name == ReferenceLookupTool.toolName }) {
            return "Custom tools must not use the reserved reference lookup name."
        }
        if !candidate.features.tools.isEmpty, !SystemLanguageModel.default.capabilities.contains(.toolCalling) {
            return "The current model does not support custom tool calls."
        }
        if !candidate.features.outputFields.isEmpty, !SystemLanguageModel.default.capabilities.contains(.guidedGeneration) {
            return "The current model does not support guided output."
        }
        if candidate.modelConfiguration.provider != .onDevice {
            return "Only the on-device model is available for evaluation runs."
        }
        if candidate.cases.isEmpty {
            return "Add at least one evaluation case."
        }
        if candidate.cases.count > Self.maximumCases {
            return "Keep the suite to \(Self.maximumCases) cases or fewer."
        }
        if !(1...5).contains(candidate.repetitions) {
            return "Choose between one and five repetitions."
        }
        let (plannedSamples, overflowed) = candidate.cases.count.multipliedReportingOverflow(by: candidate.repetitions)
        if overflowed || plannedSamples > Self.maximumPlannedSamples {
            return "Keep the run to \(Self.maximumPlannedSamples) planned samples or fewer."
        }
        if Set(candidate.cases.map(\.id)).count != candidate.cases.count {
            return "Every case needs a unique ID."
        }
        if candidate.cases.contains(where: { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Every case needs a prompt."
        }
        if candidate.instructions.count > Self.maximumFieldCharacters
            || candidate.cases.contains(where: {
                $0.prompt.count > Self.maximumFieldCharacters || $0.expected.count > Self.maximumFieldCharacters
            }) {
            return "Instructions, prompts, and expected responses must each contain \(Self.maximumFieldCharacters) characters or fewer."
        }
        let suiteCharacterCount = candidate.name.count
            + candidate.version.count
            + candidate.instructions.count
            + candidate.criteria.count
            + candidate.cases.reduce(0) { $0 + $1.name.count + $1.prompt.count + $1.expected.count }
        if suiteCharacterCount > Self.maximumCombinedSuiteCharacters {
            return "Keep the suite text to \(Self.maximumCombinedSuiteCharacters) characters or fewer."
        }
        if candidate.scoringMode.needsExpected,
           candidate.cases.contains(where: { $0.expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Every case needs expected text for the selected deterministic metric."
        }
        if candidate.scoringMode == .modelJudge {
            if candidate.rubricCriteria.isEmpty {
                return "Add at least one requirement for the AI rubric."
            }
            if candidate.rubricCriteria.count > 4 {
                return "Keep the AI rubric to four requirements or fewer so the judge can evaluate each one reliably."
            }
            if candidate.rubricCriteria.contains(where: { $0.count > Self.maximumRubricRequirementCharacters }) {
                return "Keep each rubric requirement to \(Self.maximumRubricRequirementCharacters) characters or fewer."
            }
            if !SystemLanguageModel.default.capabilities.contains(.guidedGeneration) {
                return "The selected model does not support the guided output required by the AI judge."
            }
        }
        if !(128...4_096).contains(configuration.maximumResponseTokens) {
            return "Choose a maximum response length between 128 and 4,096 tokens."
        }
        if let maximumInputTokens = configuration.maximumInputTokens,
           !(512...32_768).contains(maximumInputTokens) {
            return "Choose an input ceiling between 512 and 32,768 tokens."
        }
        if configuration.temperatureEnabled,
           !configuration.temperature.isFinite || !(0...1).contains(configuration.temperature) {
            return "Temperature must be between 0 and 1."
        }
        if configuration.samplingMode == .topK, !(1...1_000).contains(configuration.topK) {
            return "Top K must be between 1 and 1,000."
        }
        if configuration.samplingMode == .probability,
           !configuration.probabilityThreshold.isFinite || !(0.01...1).contains(configuration.probabilityThreshold) {
            return "Probability threshold must be between 0.01 and 1."
        }
        if configuration.reasoningLevel != .automatic,
           !SystemLanguageModel.default.capabilities.contains(.reasoning) {
            return "The on-device model does not support explicit reasoning levels. Choose Automatic."
        }
        if !candidate.features.tools.isEmpty, !(1...4).contains(configuration.maximumToolCalls) {
            return "The tool call limit must be between one and four calls per response."
        }
        if configuration.referenceMode == .lookupTool {
            if !SystemLanguageModel.default.capabilities.contains(.toolCalling) {
                return "The selected model does not support tool calling."
            }
            if !candidate.attachments.contains(where: { $0.kind == .text }) {
                return "Import at least one text reference before enabling reference search."
            }
            if !(1...4).contains(configuration.maximumToolCalls) {
                return "The reference tool limit must be between one and four calls per response."
            }
        }
        let allocation = configuration.contextAllocation(
            contextSize: SystemLanguageModel.default.contextSize,
            includesModelJudge: candidate.scoringMode == .modelJudge,
            customToolOutputReserve: candidate.features.tools.isEmpty ? 0 : configuration.maximumToolCalls * EvaluationCustomTool.contextTokenReservePerCall
        )
        if allocation.effectiveInputLimit < 512 {
            return "Reduce the response limit or reference-tool call limit so at least 512 input tokens remain."
        }
        if candidate.attachments.count > Self.maximumAttachments {
            return "A suite can attach up to \(Self.maximumAttachments) files."
        }
        if candidate.attachments.count(where: { $0.kind == .image }) > Self.maximumImages {
            return "A suite can attach up to \(Self.maximumImages) images."
        }
        if Set(candidate.attachments.map(\.id)).count != candidate.attachments.count {
            return "Every attachment needs a unique ID."
        }
        if candidate.attachments.contains(where: { $0.kind == .image }),
           !SystemLanguageModel.default.capabilities.contains(.vision) {
            return "The selected model does not support image input."
        }
        let status = modelStatus(for: candidate)
        return includeModelReadiness && !status.isAvailable ? status.detail : nil
    }

    private func imageInputs(for suite: EvaluationSuite) -> [ImageEvaluationInput] {
        suite.attachments
            .filter { $0.kind == .image }
            .enumerated()
            .compactMap { index, attachment in
                guard let storedFilename = attachment.storedFilename else { return nil }
                return ImageEvaluationInput(
                    label: "file-\(index + 1)",
                    url: attachmentsDirectory.appending(path: storedFilename)
                )
            }
    }

    private func importAttachments(
        _ inputs: [AttachmentInput],
        expectedRevision: String
    ) async throws {
        guard !isRunning else { throw EvaluationStoreError.runBusy }
        try requireRevision(expectedRevision)
        let prepared = try await Task.detached(priority: .userInitiated) {
            try inputs.map {
                try Self.prepareAttachment(id: $0.id, name: $0.name, mediaType: $0.mediaType, data: $0.data)
            }
        }.value
        guard !isRunning else { throw EvaluationStoreError.runBusy }
        try requireRevision(expectedRevision)
        _ = try commitPreparedAttachments(prepared)
    }

    private nonisolated static func prepareAttachment(
        id: UUID,
        name: String,
        mediaType: String,
        data: Data
    ) throws -> PreparedAttachment {
        let basename = (name as NSString).lastPathComponent
        guard !basename.isEmpty, basename == name, !name.contains("\\") else {
            throw ImportError.invalidFilename
        }
        guard let declaredType = UTType(mimeType: mediaType) else {
            throw ImportError.unsupportedType
        }
        let filenameType = UTType(filenameExtension: (name as NSString).pathExtension)
        let isImage = declaredType.conforms(to: .image)
        let isPDF = declaredType.conforms(to: .pdf)
        let isText = declaredType.conforms(to: .text)
            || declaredType.conforms(to: .json)
            || declaredType.conforms(to: .commaSeparatedText)
        guard isImage || isPDF || isText else { throw ImportError.unsupportedType }

        if let filenameType {
            let filenameCategoryMatches = (isImage && filenameType.conforms(to: .image))
                || (isPDF && filenameType.conforms(to: .pdf))
                || (isText && (filenameType.conforms(to: .text)
                    || filenameType.conforms(to: .json)
                    || filenameType.conforms(to: .commaSeparatedText)))
            guard filenameCategoryMatches else { throw ImportError.typeMismatch }
        }

        let digest = sha256(data)
        if isImage {
            guard data.count <= maximumImageBytes else { throw ImportError.imageTooLarge }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0,
                  CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                throw ImportError.unreadableImage
            }
            let fileExtension = declaredType.preferredFilenameExtension
                ?? (name as NSString).pathExtension.lowercased()
            let storedFilename = "\(id.uuidString).\(fileExtension)"
            return PreparedAttachment(
                attachment: EvaluationAttachment(
                    id: id,
                    name: name,
                    kind: .image,
                    text: nil,
                    storedFilename: storedFilename,
                    byteCount: data.count,
                    sha256: digest
                ),
                imageData: data,
                truncated: false
            )
        }

        guard data.count <= maximumTextFileBytes else { throw ImportError.fileTooLarge }
        let text: String
        if isPDF {
            guard let document = PDFDocument(data: data),
                  let extracted = document.string,
                  !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ImportError.unreadablePDF
            }
            text = extracted
        } else {
            guard let decoded = String(data: data, encoding: .utf8) else { throw ImportError.notUTF8 }
            text = decoded
        }
        let truncated = text.count > maximumExtractedTextCharacters
        return PreparedAttachment(
            attachment: EvaluationAttachment(
                id: id,
                name: name,
                kind: .text,
                text: truncated
                    ? String(text.prefix(maximumExtractedTextCharacters)) + "\n[File truncated during import.]"
                    : text,
                storedFilename: nil,
                byteCount: data.count,
                sha256: digest
            ),
            imageData: nil,
            truncated: truncated
        )
    }

    private func commitPreparedAttachments(
        _ prepared: [PreparedAttachment]
    ) throws -> [EvaluationAttachmentImportResult] {
        guard Set(prepared.map(\.attachment.id)).count == prepared.count else {
            throw EvaluationStoreError.resourceConflict("Attachment IDs must be unique.")
        }
        for item in prepared {
            if let existing = suite.attachments.first(where: { $0.id == item.attachment.id }) {
                guard existing.sha256 == item.attachment.sha256, existing.name == item.attachment.name else {
                    throw EvaluationStoreError.resourceConflict("Attachment ID already exists with different content.")
                }
            }
        }
        let newItems = prepared.filter { item in
            !suite.attachments.contains(where: { $0.id == item.attachment.id })
        }
        guard suite.attachments.count + newItems.count <= Self.maximumAttachments else {
            throw ImportError.tooManyFiles
        }
        let newImageCount = newItems.count(where: { $0.attachment.kind == .image })
        guard suite.attachments.count(where: { $0.kind == .image }) + newImageCount <= Self.maximumImages else {
            throw ImportError.tooManyImages
        }

        var writtenURLs: [URL] = []
        do {
            for item in newItems {
                guard let data = item.imageData,
                      let storedFilename = item.attachment.storedFilename else { continue }
                let url = attachmentsDirectory.appending(path: storedFilename)
                try data.write(to: url, options: .atomic)
                writtenURLs.append(url)
            }
            var candidate = suite
            candidate.attachments.append(contentsOf: newItems.map(\.attachment))
            try commitSuite(candidate)
            draftSuite.attachments = candidate.attachments
        } catch {
            for url in writtenURLs { try? FileManager.default.removeItem(at: url) }
            if let storeError = error as? EvaluationStoreError { throw storeError }
            throw EvaluationStoreError.persistence(error.localizedDescription)
        }

        let revision = try currentSuiteRevision()
        return prepared.map { item in
            EvaluationAttachmentImportResult(
                attachment: item.attachment,
                truncated: item.truncated,
                duplicate: !newItems.contains(where: { $0.attachment.id == item.attachment.id }),
                revision: revision
            )
        }
    }

    private func commitSuite(_ candidate: EvaluationSuite) throws {
        if let issue = validationIssue(for: candidate, includeModelReadiness: false) {
            throw EvaluationStoreError.invalidSuite(issue)
        }
        do {
            let data = try CanonicalJSON.data(for: candidate)
            try data.write(to: supportDirectory.appending(path: "suite.json"), options: .atomic)
            suite = candidate
        } catch {
            throw EvaluationStoreError.persistence(error.localizedDescription)
        }
    }

    private func persistRun(_ run: EvaluationRun) throws {
        do {
            try CanonicalJSON.data(for: run).write(
                to: runsDirectory.appending(path: "\(run.id.uuidString).json"),
                options: .atomic
            )
        } catch {
            throw EvaluationStoreError.persistence(error.localizedDescription)
        }
    }

    private func persistActiveRun(_ record: ActiveRunRecord) throws {
        do {
            try CanonicalJSON.data(for: record).write(to: activeRunURL, options: .atomic)
        } catch {
            throw EvaluationStoreError.persistence(error.localizedDescription)
        }
    }

    private func requireIdle() throws {
        if isRunning || activeRun != nil { throw EvaluationStoreError.runBusy }
        if isProcessingFiles { throw EvaluationStoreError.fileOperationBusy }
    }

    private func requireRevision(_ expectedRevision: String) throws {
        let current = try currentSuiteRevision()
        guard expectedRevision == current else {
            throw EvaluationStoreError.staleRevision(current: current)
        }
    }

    private func operation(for active: EvaluationActiveRun) -> EvaluationRunOperation {
        EvaluationRunOperation(
            id: active.id,
            suiteRevision: active.suiteRevision,
            phase: active.cancellationRequested
                ? .cancellationRequested
                : (isRunning ? .running : .stopped),
            completedSamples: active.completedSamples,
            totalSamples: active.totalSamples,
            startedAt: active.startedAt,
            completedAt: nil
        )
    }

    private static func revision(for suite: EvaluationSuite) throws -> String {
        let payload = SuiteRevisionPayload(
            id: suite.id,
            name: suite.name,
            version: suite.version,
            instructions: suite.instructions,
            rubricCriteria: suite.rubricCriteria,
            scoringMode: suite.scoringMode,
            repetitions: suite.repetitions,
            modelConfiguration: suite.modelConfiguration,
            features: suite.features,
            cases: suite.cases,
            attachments: suite.attachments.map {
                RevisionAttachment(
                    id: $0.id,
                    name: $0.name,
                    kind: $0.kind,
                    byteCount: $0.byteCount,
                    sha256: $0.sha256
                )
            }
        )
        return sha256(try CanonicalJSON.data(for: payload, prettyPrinted: false))
    }

    private nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func loadSuite(from directory: URL) -> (suite: EvaluationSuite?, notice: String?) {
        let url = directory.appending(path: "suite.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil) }
        do {
            let data = try Data(contentsOf: url)
            return (try CanonicalJSON.decode(EvaluationSuite.self, from: data), nil)
        } catch {
            let backup = directory.appending(path: "suite-unreadable-\(UUID().uuidString).json")
            let preserved = (try? FileManager.default.copyItem(at: url, to: backup)) != nil
            let suffix = preserved ? " It was preserved as \(backup.lastPathComponent)." : ""
            return (nil, "The saved suite could not be read.\(suffix)")
        }
    }

    private static func loadRuns(from directory: URL) -> (runs: [EvaluationRun], notice: String?) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return ([], nil) }

        var unreadableCount = 0
        let runs = urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> EvaluationRun? in
                guard let data = try? Data(contentsOf: url),
                      let run = try? CanonicalJSON.decode(EvaluationRun.self, from: data) else {
                    unreadableCount += 1
                    return nil
                }
                return run
            }
            .sorted { $0.startedAt > $1.startedAt }
        let notice = unreadableCount == 0
            ? nil
            : "\(unreadableCount) saved run\(unreadableCount == 1 ? "" : "s") could not be read and was left unchanged on disk."
        return (runs, notice)
    }

    private static func loadActiveRun(from url: URL) -> ActiveRunRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CanonicalJSON.decode(ActiveRunRecord.self, from: data)
    }

    private static func recoverInterruptedRun(
        from activeRunURL: URL,
        runsDirectory: URL,
        existingRuns: [EvaluationRun]
    ) -> (run: EvaluationRun?, notice: String?) {
        guard FileManager.default.fileExists(atPath: activeRunURL.path) else { return (nil, nil) }
        guard let record = loadActiveRun(from: activeRunURL) else {
            return (nil, "An unreadable active-run record was left unchanged for recovery.")
        }
        if existingRuns.contains(where: { $0.id == record.summary.id }) {
            try? FileManager.default.removeItem(at: activeRunURL)
            return (nil, nil)
        }

        let suite = record.suite
        let run = EvaluationRun(
            id: record.summary.id,
            suiteID: suite.id,
            suiteName: suite.name,
            suiteVersion: suite.version,
            instructions: suite.instructions,
            criteria: suite.criteria,
            scoringMode: suite.scoringMode,
            repetitions: suite.repetitions,
            judgePromptVersion: nil,
            judgePassingScore: suite.scoringMode == .modelJudge ? EvaluationSuite.judgePassingScore : nil,
            plannedSampleCount: record.summary.totalSamples,
            suiteRevision: record.summary.suiteRevision,
            plannedCases: suite.cases,
            startedAt: record.summary.startedAt,
            completedAt: Date(),
            cancelled: false,
            terminationReason: "interrupted",
            environment: EvaluationEnvironment(
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                locale: Locale.current.identifier,
                model: "On-device model (interrupted)",
                modelContextSize: 0
            ),
            attachments: suite.attachments.map {
                EvaluationAttachmentTrace(
                    name: $0.name,
                    kind: $0.kind,
                    byteCount: $0.byteCount,
                    sha256: $0.sha256
                )
            },
            results: record.results ?? []
        )
        do {
            try CanonicalJSON.data(for: run).write(
                to: runsDirectory.appending(path: "\(run.id.uuidString).json"),
                options: .atomic
            )
        } catch {
            return (nil, "The interrupted run could not be preserved: \(error.localizedDescription)")
        }
        do {
            try FileManager.default.removeItem(at: activeRunURL)
            return (run, "A run interrupted by the previous app exit was preserved in history.")
        } catch {
            return (run, "The interrupted run was preserved, but its recovery marker could not be removed: \(error.localizedDescription)")
        }
    }

    private static var hasAuthorizedPrivateCloudComputeSignature: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlement = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.private-cloud-compute" as CFString,
                nil
              ),
              entitlement as? Bool == true,
              let teamIdentifier = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.team-identifier" as CFString,
                nil
              ) as? String else { return false }
        return !teamIdentifier.isEmpty
    }
}

enum EvaluationStoreError: LocalizedError, Sendable {
    case staleRevision(current: String)
    case runBusy
    case fileOperationBusy
    case invalidSuite(String)
    case deletionConfirmationRequired
    case resourceConflict(String)
    case resourceNotFound(String)
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .staleRevision(let current):
            "The suite changed. Read it again and retry with revision \(current)."
        case .runBusy:
            "Cancel or finish the current run before changing the suite."
        case .fileOperationBusy:
            "Wait for the current file operation to finish."
        case .invalidSuite(let issue):
            issue
        case .deletionConfirmationRequired:
            "Confirm case deletion before replacing the suite."
        case .resourceConflict(let message):
            message
        case .resourceNotFound(let resource):
            "\(resource) was not found."
        case .persistence(let message):
            "The change could not be saved: \(message)"
        }
    }
}

private struct AttachmentInput: Sendable {
    var id: UUID
    var name: String
    var mediaType: String
    var data: Data
}

private struct PreparedAttachment: Sendable {
    var attachment: EvaluationAttachment
    var imageData: Data?
    var truncated: Bool
}

private struct ActiveRunRecord: Codable, Sendable {
    var summary: EvaluationActiveRun
    var suite: EvaluationSuite
    var results: [EvaluationSampleResult]?
}

private struct SuiteRevisionPayload: Codable {
    var id: UUID
    var name: String
    var version: String
    var instructions: String
    var rubricCriteria: [String]
    var scoringMode: ScoringMode
    var repetitions: Int
    var modelConfiguration: EvaluationModelConfiguration
    var features: EvaluationFeatureConfiguration
    var cases: [EvaluationCase]
    var attachments: [RevisionAttachment]
}

private struct RevisionAttachment: Codable {
    var id: UUID
    var name: String
    var kind: EvaluationAttachmentKind
    var byteCount: Int
    var sha256: String
}

private enum ImportError: LocalizedError {
    case tooManyFiles
    case tooManyImages
    case imageTooLarge
    case fileTooLarge
    case unknownFileSize
    case invalidFilename
    case unsupportedType
    case typeMismatch
    case unreadableImage
    case unreadablePDF
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .tooManyFiles: "A suite can attach up to 20 files."
        case .tooManyImages: "A suite can attach up to four images."
        case .imageTooLarge: "Images must be 10 MB or smaller."
        case .fileTooLarge: "Text and PDF files must be 5 MB or smaller."
        case .unknownFileSize: "The selected file size could not be determined."
        case .invalidFilename: "Attachment names must be plain filenames without path components."
        case .unsupportedType: "Attachments must be UTF-8 text, JSON, CSV, PDF, or an image."
        case .typeMismatch: "The declared media type does not match the filename extension."
        case .unreadableImage: "The image data could not be decoded."
        case .unreadablePDF: "The PDF contains no extractable text."
        case .notUTF8: "Text files must use UTF-8 encoding."
        }
    }
}
