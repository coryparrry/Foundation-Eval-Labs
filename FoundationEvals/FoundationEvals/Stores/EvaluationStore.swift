import CryptoKit
import Foundation
import FoundationModels
import Observation
import PDFKit
import Security
import UniformTypeIdentifiers

@MainActor
@Observable
final class EvaluationStore {
    var suite: EvaluationSuite
    var runs: [EvaluationRun]
    var selection = SidebarSelection.suite
    var isRunning = false
    var completedSamples = 0
    var totalSamples = 0
    var notice: String?
    var isImportingFiles = false
    var isProcessingFiles = false

    private let runner = EvaluationRunner()
    private let supportDirectory: URL
    private let attachmentsDirectory: URL
    private let runsDirectory: URL
    private var runTask: Task<Void, Never>?
    private var suiteSaveTask: Task<Void, Never>?

    init(supportDirectory customSupportDirectory: URL? = nil) {
        let base = customSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "FoundationEvals", directoryHint: .isDirectory)
        supportDirectory = base
        attachmentsDirectory = base.appending(path: "Attachments", directoryHint: .isDirectory)
        runsDirectory = base.appending(path: "Runs", directoryHint: .isDirectory)

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
        let loadedRuns = Self.loadRuns(from: runsDirectory)
        let initialNotice = [startupNotice, loadedSuite.notice, loadedRuns.notice]
            .compactMap { $0 }
            .joined(separator: "\n")
        suite = initialSuite
        runs = loadedRuns.runs
        notice = initialNotice.isEmpty ? nil : initialNotice
        if migratedRubric || migratedProvider { saveSuite() }
    }

    var modelStatus: ModelStatus {
        switch suite.modelConfiguration.provider {
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
        switch suite.modelConfiguration.provider {
        case .onDevice: SystemLanguageModel.default.capabilities
        case .privateCloudCompute: PrivateCloudComputeLanguageModel().capabilities
        }
    }

    var plannedSampleCount: Int {
        suite.cases.count * suite.repetitions
    }

    var plannedRequestCount: Int {
        plannedSampleCount * (suite.scoringMode == .modelJudge ? 2 : 1)
    }

    var plannedToolCallLimit: Int {
        suite.modelConfiguration.referenceMode == .lookupTool
            ? plannedSampleCount * suite.modelConfiguration.maximumToolCalls
            : 0
    }

    var runBlocker: String? {
        validationError()
    }

    func addCase() {
        suite.cases.append(
            EvaluationCase(
                name: "Case \(suite.cases.count + 1)",
                prompt: "",
                expected: ""
            )
        )
    }

    func duplicateCase(id: UUID) {
        guard let index = suite.cases.firstIndex(where: { $0.id == id }) else { return }
        var copy = suite.cases[index]
        copy.id = UUID()
        copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Copied case"
            : "\(copy.name) copy"
        suite.cases.insert(copy, at: index + 1)
    }

    func removeCase(id: UUID) {
        guard suite.cases.count > 1 else {
            notice = "An evaluation suite needs at least one case."
            return
        }
        suite.cases.removeAll { $0.id == id }
    }

    func deleteRun(id: UUID) {
        guard runs.contains(where: { $0.id == id }) else { return }
        do {
            try FileManager.default.removeItem(at: runsDirectory.appending(path: "\(id.uuidString).json"))
        } catch CocoaError.fileNoSuchFile {
            // Remove the history entry even if its backing file is already gone.
        } catch {
            notice = "Could not delete the saved run: \(error.localizedDescription)"
            return
        }

        runs.removeAll { $0.id == id }
        if selection == .run(id) {
            selection = .suite
        }
    }

    func importFiles(_ urls: [URL]) {
        guard !isRunning, !isProcessingFiles else {
            notice = "Wait for the current operation to finish before changing files."
            return
        }
        isProcessingFiles = true
        let destination = attachmentsDirectory
        let imageSlots = 4 - suite.attachments.count(where: { $0.kind == .image })

        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    try Self.importFiles(urls, to: destination, imageSlots: imageSlots)
                }.value
                suite.attachments.append(contentsOf: imported)
                saveSuite()
            } catch {
                notice = "Could not import files: \(error.localizedDescription)"
            }
            isProcessingFiles = false
        }
    }

    func removeAttachment(id: UUID) {
        guard !isRunning else {
            notice = "Cancel or finish the current run before removing files."
            return
        }
        guard let attachment = suite.attachments.first(where: { $0.id == id }) else { return }
        if let storedFilename = attachment.storedFilename {
            do {
                try FileManager.default.removeItem(at: attachmentsDirectory.appending(path: storedFilename))
            } catch CocoaError.fileNoSuchFile {
                // The suite entry still needs removing if its private copy is already gone.
            } catch {
                notice = "Could not remove the imported image: \(error.localizedDescription)"
                return
            }
        }
        suite.attachments.removeAll { $0.id == id }
        saveSuite()
    }

    func saveSuite() {
        suiteSaveTask?.cancel()
        suiteSaveTask = nil
        writeSuite()
    }

    func scheduleSuiteSave() {
        suiteSaveTask?.cancel()
        suiteSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            suiteSaveTask = nil
            writeSuite()
        }
    }

    private func writeSuite() {
        do {
            let data = try Self.encoder.encode(suite)
            try data.write(to: supportDirectory.appending(path: "suite.json"), options: .atomic)
        } catch {
            notice = "Could not save the suite: \(error.localizedDescription)"
        }
    }

    func startRun() {
        guard !isRunning else { return }
        guard !isProcessingFiles else {
            notice = "Wait for file import to finish before running the suite."
            return
        }
        guard let validationError = runBlocker else {
            let suiteSnapshot = suite
            let images = imageInputs(for: suiteSnapshot)
            isRunning = true
            completedSamples = 0
            totalSamples = suiteSnapshot.cases.count * suiteSnapshot.repetitions
            saveSuite()

            runTask = Task { [weak self] in
                guard let self else { return }
                let run = await runner.run(suite: suiteSnapshot, images: images) { [weak self] completed, total in
                    await self?.updateProgress(completed: completed, total: total)
                }
                finish(run)
            }
            return
        }
        notice = validationError
    }

    func cancelRun() {
        runTask?.cancel()
    }

    func run(with id: UUID) -> EvaluationRun? {
        runs.first { $0.id == id }
    }

    private func finish(_ run: EvaluationRun) {
        isRunning = false
        runTask = nil
        runs.insert(run, at: 0)
        selection = .run(run.id)

        do {
            let data = try Self.encoder.encode(run)
            try data.write(to: runsDirectory.appending(path: "\(run.id.uuidString).json"), options: .atomic)
        } catch {
            notice = "The run finished, but its trace could not be saved: \(error.localizedDescription)"
        }
    }

    private func updateProgress(completed: Int, total: Int) {
        completedSamples = completed
        totalSamples = total
    }

    private func validationError() -> String? {
        let configuration = suite.modelConfiguration
        if suite.cases.isEmpty {
            return "Add at least one evaluation case."
        }
        if suite.cases.contains(where: { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Every case needs a prompt."
        }
        if suite.scoringMode.needsExpected,
           suite.cases.contains(where: { $0.expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Every case needs expected text for the selected deterministic metric."
        }
        if suite.scoringMode == .modelJudge {
            if suite.rubricCriteria.isEmpty {
                return "Add at least one requirement for the AI rubric."
            }
            if suite.rubricCriteria.count > 4 {
                return "Keep the AI rubric to four requirements or fewer so the judge can evaluate each one reliably."
            }
            if !selectedModelCapabilities.contains(.guidedGeneration) {
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
        if configuration.temperatureEnabled, !(0...1).contains(configuration.temperature) {
            return "Temperature must be between 0 and 1."
        }
        if configuration.samplingMode == .topK, !(1...1_000).contains(configuration.topK) {
            return "Top K must be between 1 and 1,000."
        }
        if configuration.samplingMode == .probability,
           !(0.01...1).contains(configuration.probabilityThreshold) {
            return "Probability threshold must be between 0.01 and 1."
        }
        if configuration.reasoningLevel != .automatic,
           !selectedModelCapabilities.contains(.reasoning) {
            return "The on-device model does not support explicit reasoning levels. Choose Automatic."
        }
        if configuration.referenceMode == .lookupTool {
            if !selectedModelCapabilities.contains(.toolCalling) {
                return "The selected model does not support tool calling."
            }
            if !suite.attachments.contains(where: { $0.kind == .text }) {
                return "Import at least one text reference before enabling reference search."
            }
            if !(1...4).contains(configuration.maximumToolCalls) {
                return "The reference tool limit must be between one and four calls per response."
            }
        }
        if configuration.provider == .onDevice {
            let allocation = configuration.contextAllocation(
                contextSize: SystemLanguageModel.default.contextSize,
                includesModelJudge: suite.scoringMode == .modelJudge
            )
            if allocation.effectiveInputLimit < 512 {
                return "Reduce the response limit or reference-tool call limit so at least 512 input tokens remain."
            }
        }
        if suite.attachments.contains(where: { $0.kind == .image }),
           !selectedModelCapabilities.contains(.vision) {
            return "The selected model does not support image input."
        }
        return modelStatus.isAvailable ? nil : modelStatus.detail
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

    private nonisolated static func importFiles(
        _ urls: [URL],
        to directory: URL,
        imageSlots: Int
    ) throws -> [EvaluationAttachment] {
        var imported: [EvaluationAttachment] = []
        var remainingImages = imageSlots

        do {
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                let type = UTType(filenameExtension: url.pathExtension)
                let isImage = type?.conforms(to: .image) == true
                if isImage {
                    guard remainingImages > 0 else { throw ImportError.tooManyImages }
                }
                guard let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    throw ImportError.unknownFileSize
                }
                guard byteCount <= (isImage ? 10_000_000 : 5_000_000) else {
                    throw isImage ? ImportError.imageTooLarge : ImportError.fileTooLarge
                }

                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                let id = UUID()

                if isImage {
                    let fileExtension = url.pathExtension.lowercased()
                    let storedFilename = "\(id.uuidString).\(fileExtension)"
                    try data.write(to: directory.appending(path: storedFilename), options: .atomic)
                    imported.append(
                        EvaluationAttachment(
                            id: id,
                            name: url.lastPathComponent,
                            kind: .image,
                            text: nil,
                            storedFilename: storedFilename,
                            byteCount: data.count,
                            sha256: digest
                        )
                    )
                    remainingImages -= 1
                    continue
                }

                let text: String
                if type?.conforms(to: .pdf) == true {
                    guard let document = PDFDocument(data: data), let extracted = document.string else {
                        throw ImportError.unreadablePDF
                    }
                    text = extracted
                } else {
                    guard let decoded = String(data: data, encoding: .utf8) else {
                        throw ImportError.notUTF8
                    }
                    text = decoded
                }
                let limit = 16_000
                imported.append(
                    EvaluationAttachment(
                        id: id,
                        name: url.lastPathComponent,
                        kind: .text,
                        text: text.count > limit ? String(text.prefix(limit)) + "\n[File truncated during import.]" : text,
                        storedFilename: nil,
                        byteCount: data.count,
                        sha256: digest
                    )
                )
            }
            return imported
        } catch {
            for filename in imported.compactMap(\.storedFilename) {
                try? FileManager.default.removeItem(at: directory.appending(path: filename))
            }
            throw error
        }
    }

    private static func loadSuite(from directory: URL) -> (suite: EvaluationSuite?, notice: String?) {
        let url = directory.appending(path: "suite.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil) }
        do {
            let data = try Data(contentsOf: url)
            return (try decoder.decode(EvaluationSuite.self, from: data), nil)
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
                      let run = try? decoder.decode(EvaluationRun.self, from: data) else {
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

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

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

private enum ImportError: LocalizedError {
    case tooManyImages
    case imageTooLarge
    case fileTooLarge
    case unknownFileSize
    case unreadablePDF
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .tooManyImages: "A suite can attach up to four images."
        case .imageTooLarge: "Images must be 10 MB or smaller."
        case .fileTooLarge: "Text and PDF files must be 5 MB or smaller."
        case .unknownFileSize: "The selected file size could not be determined."
        case .unreadablePDF: "The PDF contains no extractable text."
        case .notUTF8: "Text files must use UTF-8 encoding."
        }
    }
}
