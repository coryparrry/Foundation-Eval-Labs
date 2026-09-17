import Foundation
import FoundationEvalsAppleBridge
import FoundationEvalsIntegration

enum EvidenceImportService {
    nonisolated static func preview(
        url: URL,
        destinationProjectID: UUID,
        destinationSuiteID: UUID,
        destinationProjectName: String,
        suiteName: String,
        existing: [EvidenceImportIndexRecord],
        stagingParent: URL
    ) throws -> EvidenceImportPreview {
        let stagingRoot = stagingParent.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        do {
            let staged = try stage(url: url, into: stagingRoot)
            return try decodePreview(
                staged: staged,
                stagingRoot: stagingRoot,
                destinationProjectID: destinationProjectID,
                destinationSuiteID: destinationSuiteID,
                destinationProjectName: destinationProjectName,
                suiteName: suiteName,
                existing: existing
            )
        } catch {
            try? FileManager.default.removeItem(at: stagingRoot)
            throw error
        }
    }

    nonisolated static func discard(stagingRoot: URL) {
        try? FileManager.default.removeItem(at: stagingRoot)
    }

    private nonisolated static func stage(url: URL, into stagingRoot: URL) throws -> StagedImport {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw CaptureFileIOError.symlinkRejected
        }
        if values.isDirectory == true {
            return try stageDirectory(url, into: stagingRoot)
        }
        guard values.isRegularFile == true else {
            throw CaptureFileIOError.notRegularFile
        }
        let data = try CaptureFileIO.readRegularFileNoFollow(
            at: url,
            maximumBytes: CaptureLimits.version1.maximumAppleJSONBytes
        )
        let name = url.lastPathComponent.isEmpty ? "source.json" : url.lastPathComponent
        try CaptureFileIO.writeAtomically(data, to: stagingRoot.appending(path: name))
        return StagedImport(filename: name, files: [name: data])
    }

    private nonisolated static func stageDirectory(_ root: URL, into stagingRoot: URL) throws -> StagedImport {
        var files: [String: Data] = [:]
        var total = 0
        try walk(root: root, relative: "", stagingRoot: stagingRoot, files: &files, total: &total)
        return StagedImport(filename: root.lastPathComponent, files: files)
    }

    private nonisolated static func walk(
        root: URL,
        relative: String,
        stagingRoot: URL,
        files: inout [String: Data],
        total: inout Int
    ) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        guard files.count + contents.count <= CaptureLimits.version1.maximumRegularFiles else {
            throw CaptureFileIOError.tooLarge(maximumBytes: CaptureLimits.version1.maximumBundleBytes)
        }
        for child in contents {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw CaptureFileIOError.symlinkRejected
            }
            let name = child.lastPathComponent
            let nextRelative = relative.isEmpty ? name : "\(relative)/\(name)"
            _ = try CaptureFileIO.relativePathComponents(nextRelative)
            if values.isDirectory == true {
                try FileManager.default.createDirectory(
                    at: stagingRoot.appending(path: nextRelative, directoryHint: .isDirectory),
                    withIntermediateDirectories: true
                )
                try walk(root: child, relative: nextRelative, stagingRoot: stagingRoot, files: &files, total: &total)
                continue
            }
            guard values.isRegularFile == true else { throw CaptureFileIOError.notRegularFile }
            let remaining = CaptureLimits.version1.maximumBundleBytes - total
            let data = try CaptureFileIO.readRegularFileNoFollow(at: child, maximumBytes: remaining)
            total += data.count
            guard total <= CaptureLimits.version1.maximumBundleBytes else {
                throw CaptureFileIOError.tooLarge(maximumBytes: CaptureLimits.version1.maximumBundleBytes)
            }
            try CaptureFileIO.writeAtomically(data, to: stagingRoot.appending(path: nextRelative))
            files[nextRelative] = data
        }
    }

    private nonisolated static func decodePreview(
        staged: StagedImport,
        stagingRoot: URL,
        destinationProjectID: UUID,
        destinationSuiteID: UUID,
        destinationProjectName: String,
        suiteName: String,
        existing: [EvidenceImportIndexRecord]
    ) throws -> EvidenceImportPreview {
        if staged.files["manifest.json"] != nil {
            let bundle = try CaptureBundleValidator.load(root: stagingRoot, stagedBytes: staged.files)
            let run = try EvidenceImportMapper.run(
                from: bundle,
                destinationProjectID: destinationProjectID,
                destinationSuiteID: destinationSuiteID,
                suiteName: suiteName
            )
            return makePreview(
                run: run,
                filename: staged.filename,
                destinationProjectID: destinationProjectID,
                destinationSuiteID: destinationSuiteID,
                destinationProjectName: destinationProjectName,
                stagingRoot: stagingRoot,
                existing: existing,
                canNormalize: true
            )
        }

        guard staged.files.count == 1, let data = staged.files.values.first else {
            throw EvidenceImportError.unsupportedContent("Select a .fevalrun folder or a single JSON file.")
        }
        try JSONStructure.validate(
            data,
            maximumDepth: CaptureLimits.version1.maximumJSONNestingDepth,
            rejectDuplicateKeys: false
        )
        if let inspection = try? AppleEvaluationCodec.inspect(bytes: data) {
            let run = EvidenceImportMapper.run(
                from: inspection,
                destinationProjectID: destinationProjectID,
                destinationSuiteID: destinationSuiteID,
                suiteName: suiteName
            )
            return makePreview(
                run: run,
                filename: staged.filename,
                destinationProjectID: destinationProjectID,
                destinationSuiteID: destinationSuiteID,
                destinationProjectName: destinationProjectName,
                stagingRoot: stagingRoot,
                existing: existing,
                canNormalize: !inspection.samples.isEmpty
            )
        }
        if let inspection = try? AppleTranscriptCodec.inspect(bytes: data) {
            let run = EvidenceImportMapper.run(
                from: inspection,
                destinationProjectID: destinationProjectID,
                destinationSuiteID: destinationSuiteID,
                suiteName: suiteName
            )
            return makePreview(
                run: run,
                filename: staged.filename,
                destinationProjectID: destinationProjectID,
                destinationSuiteID: destinationSuiteID,
                destinationProjectName: destinationProjectName,
                stagingRoot: stagingRoot,
                existing: existing,
                canNormalize: false
            )
        }
        throw EvidenceImportError.unsupportedContent("The file is not a supported capture bundle, Apple evaluation result, or transcript.")
    }

    private nonisolated static func makePreview(
        run: EvaluationRun,
        filename: String,
        destinationProjectID: UUID,
        destinationSuiteID: UUID,
        destinationProjectName: String,
        stagingRoot: URL,
        existing: [EvidenceImportIndexRecord],
        canNormalize: Bool
    ) -> EvidenceImportPreview {
        let evidence = run.importedEvidence
        let digest = evidence?.sourceDigest ?? ""
        let producerRunID = evidence?.producerRunID
        let outcome: EvidenceImportOutcome
        if let match = existing.first(where: { $0.producerRunID == producerRunID && $0.sourceDigest == digest })
            ?? existing.first(where: { producerRunID == nil && $0.sourceDigest == digest }) {
            outcome = .alreadyImported(match.ownedRunID)
        } else if let producerRunID, let conflict = existing.first(where: { $0.producerRunID == producerRunID && $0.sourceDigest != digest }) {
            outcome = .conflict(conflict.ownedRunID)
        } else {
            outcome = .readyToImport
        }
        return EvidenceImportPreview(
            destinationProjectID: destinationProjectID,
            destinationSuiteID: destinationSuiteID,
            destinationProjectName: destinationProjectName,
            sourceKind: evidence?.sourceKind ?? .unsupportedJSON,
            filename: filename,
            warnings: evidence?.warnings ?? [EvaluationImportedLabels.inspectionOnly],
            coverageLabel: evidence?.coverageLabel ?? EvaluationImportedLabels.plannedUnknown,
            featureClaim: [evidence?.producerAppID, evidence?.producerFeatureID].compactMap { $0 }.joined(separator: " · "),
            environmentSummary: evidence?.environmentClaims["operatingSystem"] ?? "Unknown producer environment",
            sampleCount: run.results.count,
            canNormalize: canNormalize,
            outcome: outcome,
            sourceDigest: digest,
            producerRunID: producerRunID,
            stagingRoot: stagingRoot,
            run: run
        )
    }
}

private struct StagedImport: Sendable {
    var filename: String
    var files: [String: Data]
}
