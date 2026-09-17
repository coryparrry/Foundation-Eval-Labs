import CryptoKit
import Foundation

struct EvaluationWorkspaceBootstrap {
    var catalog: EvaluationWorkspaceCatalog
    var notice: String?
}

enum EvaluationWorkspacePersistence {
    static let catalogFilename = "workspace-v1.json"
    static let legacyStateMigrationFilename = "legacy-state-migration-v1.complete"

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
            // An older app may have omitted local state during the first migration.
            // Recover that omission once, without granting historical decisions authority.
            // Never replace a damaged established destination with a legacy snapshot.
            do {
                try createSuiteDirectories(at: target)
                let recovered = try copyLegacyStateIfMissing(from: supportDirectory, to: target)
                guard recovered else {
                    return EvaluationWorkspaceBootstrap(catalog: catalog)
                }

                var repairedCatalog = catalog
                repairedCatalog.migratedLegacyStorageAt = Date(
                    timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)
                )
                try save(repairedCatalog, in: supportDirectory)
                return EvaluationWorkspaceBootstrap(
                    catalog: repairedCatalog,
                    notice: "An older local-state snapshot was recovered for inspection. Its approvals, corrections, reviewed examples and experiment decisions are not active; review the retained run evidence again before approving a baseline."
                )
            } catch {
                // Atomic writes have no application-owned partial destination to remove.
                // In particular, a decode failure is not proof that we own the file.
                return EvaluationWorkspaceBootstrap(
                    catalog: catalog,
                    notice: "Legacy state could not be recovered: \(error.localizedDescription)"
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
            if FileManager.default.fileExists(atPath: target.appending(path: "state.json").path) {
                try markLegacyStateMigrated(in: target)
            }
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

    static func legacyStateWasMigrated(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: legacyStateMigrationFilename).path)
    }

    private static func markLegacyStateMigrated(in directory: URL) throws {
        try Data("1\n".utf8).write(
            to: directory.appending(path: legacyStateMigrationFilename), options: .atomic
        )
    }

    /// The immutable recovery copy doubles as a content-addressed quarantine marker.
    /// A subsequently saved, independently reviewed state has different bytes.
    static func legacyStateRecoveryURL(for data: Data, in directory: URL) -> URL {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "state-legacy-recovered-\(digest).json")
    }

    private static func copyLegacyStateIfMissing(from source: URL, to target: URL) throws -> Bool {
        guard !legacyStateWasMigrated(in: target) else { return false }
        let destination = target.appending(path: "state.json")
        if FileManager.default.fileExists(atPath: destination.path) {
            // Even unreadable current bytes may contain newer revocations. Preserve them.
            try markLegacyStateMigrated(in: target)
            return false
        }
        let legacy = source.appending(path: "state.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return false }
        let data = try Data(contentsOf: legacy)
        let recovery = legacyStateRecoveryURL(for: data, in: target)
        // Establish quarantine before making the historical bytes loadable. A failed
        // backup leaves the canonical destination untouched; a failed copy is retryable.
        if !FileManager.default.fileExists(atPath: recovery.path) {
            try data.write(to: recovery, options: .atomic)
        }
        try data.write(to: destination, options: .atomic)
        try markLegacyStateMigrated(in: target)
        return true
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
