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
            return EvaluationWorkspaceBootstrap(catalog: catalog)
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
            migratedLegacyStorageAt: legacySuite == nil ? nil : now
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
        try save(catalog, in: supportDirectory)
        // Reassign to force a complete value before returning under strict concurrency.
        catalog.migratedLegacyStorageAt = migrated ? now : catalog.migratedLegacyStorageAt
        if migrated {
            try save(catalog, in: supportDirectory)
        }
        return EvaluationWorkspaceBootstrap(
            catalog: catalog,
            notice: migrated
                ? "Your existing suite, draft, attachments, and run history were copied into the new workspace. The legacy files were left unchanged for recovery."
                : nil
        )
    }

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

    private static func copyLegacyStorage(from source: URL, to target: URL) throws -> Bool {
        let mappings = [
            (source.appending(path: "suite.json"), target.appending(path: "suite.json")),
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
