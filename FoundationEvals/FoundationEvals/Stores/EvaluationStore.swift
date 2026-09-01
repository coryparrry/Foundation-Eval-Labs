import CryptoKit
import Foundation
import FoundationModels
import Observation
import PDFKit
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

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        if migratedRubric {
            initialSuite.criteria = EvaluationSuite.defaultRubric
            if initialSuite.cases.count == 1,
               initialSuite.cases[0].prompt == "Explain why the sky appears blue in two sentences.",
               initialSuite.cases[0].expected.isEmpty {
                initialSuite.cases[0].expected = EvaluationSuite().cases[0].expected
            }
        }
        let initialNotice = [startupNotice, loadedSuite.notice].compactMap { $0 }.joined(separator: "\n")
        suite = initialSuite
        runs = Self.loadRuns(from: runsDirectory)
        notice = initialNotice.isEmpty ? nil : initialNotice
        if migratedRubric { saveSuite() }
    }

    var modelStatus: ModelStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            ModelStatus(isAvailable: true, label: "Model ready", detail: "Apple's on-device system language model is available.")
        case .unavailable(.deviceNotEligible):
            ModelStatus(isAvailable: false, label: "Device not eligible", detail: "This Mac does not support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            ModelStatus(isAvailable: false, label: "Apple Intelligence off", detail: "Enable Apple Intelligence in System Settings.")
        case .unavailable(.modelNotReady):
            ModelStatus(isAvailable: false, label: "Model not ready", detail: "The model may still be downloading.")
        case .unavailable:
            ModelStatus(isAvailable: false, label: "Model unavailable", detail: "The model is unavailable for an unknown reason.")
        }
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

    func removeCase(id: UUID) {
        guard suite.cases.count > 1 else {
            notice = "An evaluation suite needs at least one case."
            return
        }
        suite.cases.removeAll { $0.id == id }
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
        guard let validationError = validationError() else {
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

    private static func loadRuns(from directory: URL) -> [EvaluationRun] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(EvaluationRun.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
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
