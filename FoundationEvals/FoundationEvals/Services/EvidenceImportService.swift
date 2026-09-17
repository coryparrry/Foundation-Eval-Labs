import Darwin
import Foundation
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
        var visited = 1
        let rootFD = try CaptureFileIO.openDirectoryNoFollow(at: root)
        defer { close(rootFD) }
        try walk(
            directoryFD: rootFD,
            relative: "",
            depth: 1,
            stagingRoot: stagingRoot,
            files: &files,
            total: &total,
            visited: &visited
        )
        return StagedImport(filename: root.lastPathComponent, files: files)
    }

    private nonisolated static func walk(
        directoryFD: Int32,
        relative: String,
        depth: Int,
        stagingRoot: URL,
        files: inout [String: Data],
        total: inout Int,
        visited: inout Int
    ) throws {
        if Task.isCancelled { throw EvidenceImportError.cancelled }
        guard depth <= CaptureLimits.version1.maximumDirectoryDepth else {
            throw CaptureFileIOError.directoryTooDeep
        }
        let names = try CaptureFileIO.directoryNames(from: directoryFD)
        visited += names.count
        guard visited <= CaptureLimits.version1.maximumVisitedEntries else {
            throw CaptureFileIOError.tooManyEntries
        }
        for name in names {
            if Task.isCancelled { throw EvidenceImportError.cancelled }
            let nextRelative = relative.isEmpty ? name : "\(relative)/\(name)"
            _ = try CaptureFileIO.relativePathComponents(nextRelative)
            if let childFD = try? CaptureFileIO.openMemberNoFollow(directoryFD: directoryFD, name: name, directory: true) {
                defer { close(childFD) }
                try FileManager.default.createDirectory(
                    at: stagingRoot.appending(path: nextRelative, directoryHint: .isDirectory),
                    withIntermediateDirectories: true
                )
                try walk(
                    directoryFD: childFD,
                    relative: nextRelative,
                    depth: depth + 1,
                    stagingRoot: stagingRoot,
                    files: &files,
                    total: &total,
                    visited: &visited
                )
                continue
            }
            let fileFD = try CaptureFileIO.openMemberNoFollow(directoryFD: directoryFD, name: name, directory: false)
            defer { close(fileFD) }
            let remaining = CaptureLimits.version1.maximumBundleBytes - total
            let data = try CaptureFileIO.readRegularFileNoFollow(fromFileFD: fileFD, maximumBytes: remaining, name: name)
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
        if let inspection = try? AppleEvaluationJSONInspector.inspect(bytes: data) {
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
        let outcome = EvidenceImportIndex.outcome(
            producerRunID: producerRunID,
            sourceDigest: digest,
            records: existing
        )
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
