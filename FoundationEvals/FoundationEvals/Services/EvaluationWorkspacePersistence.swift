import CryptoKit
import Foundation

struct EvaluationWorkspaceBootstrap {
    var catalog: EvaluationWorkspaceCatalog
    var notice: String?
}

enum EvaluationWorkspacePersistence {
    static let catalogFilename = "workspace-v1.json"

    static func bootstrap(
        in supportDirectory: URL,
        legacySuite: EvaluationSuite?
    ) throws -> EvaluationWorkspaceBootstrap {
        let catalogURL = supportDirectory.appending(path: catalogFilename)
        if FileManager.default.fileExists(atPath: catalogURL.path) {
            let catalog = try CanonicalJSON.decode(
                EvaluationWorkspaceCatalog.self,
                from: Data(contentsOf: catalogURL)
            )
            guard catalog.formatVersion == EvaluationWorkspaceCatalog.currentFormatVersion,
                  !catalog.projects.isEmpty else {
                throw EvaluationWorkspaceError.unsupportedCatalog
            }

            guard let legacySuite,
                  let matchingProject = catalog.projects.first(where: {
                      $0.suites.contains { $0.id == legacySuite.id }
                  }),
                  let matchingSuite = matchingProject.suites.first(where: {
                      $0.id == legacySuite.id
                  }) else {
                return EvaluationWorkspaceBootstrap(catalog: catalog)
            }

            let target = suiteDirectory(
                supportDirectory: supportDirectory,
                projectID: matchingProject.id,
                suiteID: matchingSuite.id
            )
            // A catalog means the original workspace migration already ran. Repair
            // only the local-state omission; recopying stale suite, attachment, or
            // run files into an established workspace would broaden the recovery.
            do {
                try createSuiteDirectories(at: target)
                let migrated = try copyLegacyStateIfMissing(from: supportDirectory, to: target)
                guard migrated else {
                    return EvaluationWorkspaceBootstrap(catalog: catalog)
                }

                var repairedCatalog = catalog
                repairedCatalog.migratedLegacyStorageAt = Date(
                    timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)
                )
                try save(repairedCatalog, in: supportDirectory)
                return EvaluationWorkspaceBootstrap(
                    catalog: repairedCatalog,
                    notice: legacyMigrationNotice
                )
            } catch {
                removeUnreadablePartialStateIfRetryable(supportDirectory: supportDirectory, target: target)
                return EvaluationWorkspaceBootstrap(
                    catalog: catalog,
                    notice: "Legacy state could not be repaired: \(error.localizedDescription)"
                )
            }
        }

        let now = Date()
        let seedSuite = legacySuite ?? EvaluationSuite()
        let suiteRecord = EvaluationSuiteRecord(
            id: seedSuite.id,
            name: seedSuite.name,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil,
            repositoryDefinitionPath: nil,
            lastRepositoryRevision: nil
        )
        let project = EvaluationProject(
            id: UUID(),
            name: legacySuite == nil ? "My App" : "Imported workspace",
            createdAt: now,
            updatedAt: now,
            archivedAt: nil,
            repository: nil,
            selectedSuiteID: seedSuite.id,
            suites: [suiteRecord]
        )
        var catalog = EvaluationWorkspaceCatalog(
            selectedProjectID: project.id,
            projects: [project],
            migratedLegacyStorageAt: nil
        )
        let target = suiteDirectory(
            supportDirectory: supportDirectory,
            projectID: project.id,
            suiteID: seedSuite.id
        )
        try createSuiteDirectories(at: target)

        var migrated = false
        if legacySuite != nil {
            migrated = try copyLegacyStorage(from: supportDirectory, to: target)
        }
        let suiteURL = target.appending(path: "suite.json")
        if !FileManager.default.fileExists(atPath: suiteURL.path) {
            try CanonicalJSON.data(for: seedSuite).write(to: suiteURL, options: .atomic)
        }
        if migrated {
            catalog.migratedLegacyStorageAt = now
        }
        try save(catalog, in: supportDirectory)
        return EvaluationWorkspaceBootstrap(
            catalog: catalog,
            notice: migrated ? legacyMigrationNotice : nil
        )
    }

    private static let legacyMigrationNotice =
        "Existing legacy files were copied into the matching workspace suite where destinations were missing. The legacy files were left unchanged for recovery."

    static func save(_ catalog: EvaluationWorkspaceCatalog, in supportDirectory: URL) throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try CanonicalJSON.data(for: catalog).write(
            to: supportDirectory.appending(path: catalogFilename),
            options: .atomic
        )
    }

    static func suiteDirectory(
        supportDirectory: URL,
        projectID: UUID,
        suiteID: UUID
    ) -> URL {
        supportDirectory
            .appending(path: "Projects", directoryHint: .isDirectory)
            .appending(path: projectID.uuidString, directoryHint: .isDirectory)
            .appending(path: "Suites", directoryHint: .isDirectory)
            .appending(path: suiteID.uuidString, directoryHint: .isDirectory)
    }

    static func createSuiteDirectories(at suiteDirectory: URL) throws {
        try FileManager.default.createDirectory(at: suiteDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: suiteDirectory.appending(path: "Attachments", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: suiteDirectory.appending(path: "Runs", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    static func repositoryDefinitionURL(
        project: EvaluationProject,
        suite: EvaluationSuiteRecord
    ) -> URL? {
        guard let repository = project.repository,
              let relativePath = suite.repositoryDefinitionPath,
              safeRelativePath(relativePath) else { return nil }
        return URL(filePath: repository.rootPath, directoryHint: .isDirectory)
            .appending(path: relativePath)
    }

    static func definitionRevision(_ definition: EvaluationSuiteDefinition) throws -> String {
        let data = try CanonicalJSON.data(for: definition, prettyPrinted: false)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func safeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    static func copyLegacyStorage(from source: URL, to target: URL) throws -> Bool {
        let mappings = [
            (source.appending(path: "suite.json"), target.appending(path: "suite.json")),
            (source.appending(path: "state.json"), target.appending(path: "state.json")),
            (source.appending(path: "suite-draft.json"), target.appending(path: "suite-draft.json")),
            (source.appending(path: "active-run.json"), target.appending(path: "active-run.json")),
            (source.appending(path: "Attachments", directoryHint: .isDirectory),
             target.appending(path: "Attachments", directoryHint: .isDirectory)),
            (source.appending(path: "Runs", directoryHint: .isDirectory),
             target.appending(path: "Runs", directoryHint: .isDirectory))
        ]
        var copied = false
        for (legacy, destination) in mappings where FileManager.default.fileExists(atPath: legacy.path) {
            if legacy.hasDirectoryPath {
                guard let children = try? FileManager.default.contentsOfDirectory(
                    at: legacy,
                    includingPropertiesForKeys: nil
                ) else { continue }
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                for child in children {
                    let targetChild = destination.appending(path: child.lastPathComponent)
                    guard !FileManager.default.fileExists(atPath: targetChild.path) else { continue }
                    try FileManager.default.copyItem(at: child, to: targetChild)
                    copied = true
                }
            } else if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: legacy, to: destination)
                copied = true
            }
        }
        return copied
    }

    private static func copyLegacyStateIfMissing(from source: URL, to target: URL) throws -> Bool {
        let legacy = source.appending(path: "state.json")
        let destination = target.appending(path: "state.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return false }
        if !FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.copyItem(at: legacy, to: destination)
            } catch {
                // Remove a partial copy so the next launch retries. The legacy
                // source is left unchanged for recovery.
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            return true
        }
        // The destination exists. A decodable destination always wins, even over
        // a newer legacy file. But an undecodable destination (for example a
        // partial copy left by an earlier failed repair) would otherwise block
        // every later launch on the existence check above, so it is replaced
        // from legacy when legacy itself decodes. When both sides are
        // undecodable there is nothing to recover from, and the destination is
        // left for loadSuiteLocalState to preserve and report.
        let destinationData = try? Data(contentsOf: destination)
        let destinationDecodes = destinationData.map {
            (try? CanonicalJSON.decode(EvaluationSuiteLocalState.self, from: $0)) != nil
        } ?? false
        guard !destinationDecodes,
              let legacyData = try? Data(contentsOf: legacy),
              (try? CanonicalJSON.decode(EvaluationSuiteLocalState.self, from: legacyData)) != nil else {
            return false
        }
        if let destinationData {
            preserveUnreadableState(at: destination, data: destinationData)
        }
        do {
            try FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: legacy, to: destination)
        } catch {
            // Remove a partial replacement so the next launch retries. The
            // legacy source is left unchanged for recovery.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return true
    }

    /// Best-effort backup beside an unreadable state file, mirroring the
    /// preservation that loadSuiteLocalState performs on decode failure.
    private static func preserveUnreadableState(at url: URL, data: Data) {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let backup = url.deletingLastPathComponent()
            .appending(path: "state-unreadable-\(digest).json", directoryHint: .notDirectory)
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? data.write(to: backup, options: .atomic)
    }

    /// Removes a repair leftover so a later launch retries the copy. Only an
    /// unreadable destination is removed, and only when the legacy source
    /// still exists. A valid pre-existing destination is always preserved, and
    /// loadSuiteLocalState tolerates decode failure, so removal stays recoverable.
    static func removeUnreadablePartialStateIfRetryable(supportDirectory: URL, target: URL) {
        let legacyURL = supportDirectory.appending(path: "state.json")
        let destinationURL = target.appending(path: "state.json")
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              FileManager.default.fileExists(atPath: destinationURL.path),
              let data = try? Data(contentsOf: destinationURL),
              (try? CanonicalJSON.decode(EvaluationSuiteLocalState.self, from: data)) == nil else { return }
        try? FileManager.default.removeItem(at: destinationURL)
    }
}

enum EvaluationWorkspaceError: LocalizedError, Sendable {
    case unsupportedCatalog
    case missingProject
    case missingSuite
    case invalidRepositoryPath
    case repositoryConflict

    var errorDescription: String? {
        switch self {
        case .unsupportedCatalog: "The workspace catalog is empty or uses a newer unsupported format."
        case .missingProject: "The selected project no longer exists."
        case .missingSuite: "The selected suite no longer exists."
        case .invalidRepositoryPath: "The repository suite path must be a safe relative path."
        case .repositoryConflict: "The repository suite changed outside Foundation Evals. Review or reload it before saving."
        }
    }
}

enum EvaluationRepositoryInspector {
    static func snapshot(rootPath: String) async -> EvaluationRepositorySnapshot {
        await Task.detached(priority: .utility) {
            let capturedAt = Date()
            do {
                let commit = try runGit(["rev-parse", "HEAD"], rootPath: rootPath)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let status = try runGit(["status", "--porcelain=v1", "--untracked-files=normal"], rootPath: rootPath)
                return EvaluationRepositorySnapshot(
                    rootPath: rootPath,
                    commit: commit.isEmpty ? nil : commit,
                    isDirty: !status.isEmpty,
                    capturedAt: capturedAt,
                    error: nil
                )
            } catch {
                return EvaluationRepositorySnapshot(
                    rootPath: rootPath,
                    commit: nil,
                    isDirty: nil,
                    capturedAt: capturedAt,
                    error: error.localizedDescription
                )
            }
        }.value
    }

    private static func runGit(_ arguments: [String], rootPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", rootPath] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw EvaluationRepositoryInspectionError.git(message.isEmpty ? "Git inspection failed." : message)
        }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .newlines)
    }
}

private enum EvaluationRepositoryInspectionError: LocalizedError {
    case git(String)

    var errorDescription: String? {
        switch self { case .git(let message): message }
    }
}
