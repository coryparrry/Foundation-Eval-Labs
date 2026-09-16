import Foundation
import Testing
@testable import FoundationEvals

@MainActor
struct EvaluationWorkspaceRepairTests {
    @Test func unreadablePartialIsRemovedWhenLegacyExists() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let validState = EvaluationSuiteLocalState()
        let validData = try CanonicalJSON.data(for: validState)
        try validData.write(to: directory.appending(path: "state.json"), options: .atomic)
        try Data("{ not valid state".utf8).write(to: target.appending(path: "state.json"), options: .atomic)

        EvaluationWorkspacePersistence.removeUnreadablePartialStateIfRetryable(
            supportDirectory: directory,
            target: target
        )

        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "state.json").path))
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == validData)
    }

    @Test func validDestinationIsPreserved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        var state = EvaluationSuiteLocalState()
        state.humanCorrections = []
        let validData = try CanonicalJSON.data(for: state)
        try validData.write(to: directory.appending(path: "state.json"), options: .atomic)
        try validData.write(to: target.appending(path: "state.json"), options: .atomic)

        EvaluationWorkspacePersistence.removeUnreadablePartialStateIfRetryable(
            supportDirectory: directory,
            target: target
        )

        #expect(try Data(contentsOf: target.appending(path: "state.json")) == validData)
    }

    @Test func corruptDestinationWithoutLegacyIsPreserved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appending(path: "target", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let corrupt = Data("{ not valid state".utf8)
        try corrupt.write(to: target.appending(path: "state.json"), options: .atomic)

        EvaluationWorkspacePersistence.removeUnreadablePartialStateIfRetryable(
            supportDirectory: directory,
            target: target
        )

        #expect(try Data(contentsOf: target.appending(path: "state.json")) == corrupt)
    }

    @Test func corruptDestinationIsReplacedFromValidLegacyAndHeals() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var suite = EvaluationSuite()
        suite.id = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let legacyData = try CanonicalJSON.data(for: EvaluationSuiteLocalState())
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try legacyData.write(to: directory.appending(path: "state.json"))

        let fixture = existingCatalog(legacySuiteID: suite.id)
        try EvaluationWorkspacePersistence.save(fixture.catalog, in: directory)
        let target = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory,
            projectID: fixture.legacyProjectID,
            suiteID: suite.id
        )
        try EvaluationWorkspacePersistence.createSuiteDirectories(at: target)
        try CanonicalJSON.data(for: suite).write(to: target.appending(path: "suite.json"))
        let corrupt = Data("{ not valid state".utf8)
        try corrupt.write(to: target.appending(path: "state.json"))

        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: suite
        )

        #expect(bootstrap.notice != nil)
        #expect(bootstrap.catalog.migratedLegacyStorageAt != nil)
        #expect(try Data(contentsOf: target.appending(path: "state.json")) == legacyData)
        // The undecodable bytes are preserved beside the repaired file.
        let preserved = try FileManager.default.contentsOfDirectory(atPath: target.path)
            .filter { $0.hasPrefix("state-unreadable-") }
        #expect(preserved.count == 1)
        #expect(try Data(contentsOf: target.appending(path: preserved[0])) == corrupt)
        // The legacy source is left unchanged for recovery.
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == legacyData)

        let repeatBootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: suite
        )
        #expect(repeatBootstrap.notice == nil)
        #expect(repeatBootstrap.catalog.migratedLegacyStorageAt == bootstrap.catalog.migratedLegacyStorageAt)
        #expect(try Data(contentsOf: target.appending(path: "state.json")) == legacyData)
    }

    @Test func corruptDestinationWithCorruptLegacyIsLeftForLoadNotice() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var suite = EvaluationSuite()
        suite.id = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try Data("{ legacy not valid".utf8).write(to: directory.appending(path: "state.json"))

        let fixture = existingCatalog(legacySuiteID: suite.id)
        try EvaluationWorkspacePersistence.save(fixture.catalog, in: directory)
        let target = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory,
            projectID: fixture.legacyProjectID,
            suiteID: suite.id
        )
        try EvaluationWorkspacePersistence.createSuiteDirectories(at: target)
        try CanonicalJSON.data(for: suite).write(to: target.appending(path: "suite.json"))
        let corruptDestination = Data("{ destination not valid".utf8)
        try corruptDestination.write(to: target.appending(path: "state.json"))

        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: suite
        )

        // Nothing to recover from: the destination is preserved untouched and no
        // repair notice is claimed. loadSuiteLocalState still preserves and
        // reports the undecodable file on load.
        #expect(bootstrap.notice == nil)
        #expect(bootstrap.catalog.migratedLegacyStorageAt == nil)
        #expect(try Data(contentsOf: target.appending(path: "state.json")) == corruptDestination)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: target.path)
                .filter { $0.hasPrefix("state-unreadable-") }.isEmpty
        )
    }

    @Test func duplicateImportWithStaleRevisionStaysIdempotent() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let id = UUID()
        let data = Data("duplicate reference".utf8)
        let first = try await store.importAttachment(
            id: id,
            name: "reference.txt",
            mediaType: "text/plain",
            data: data,
            expectedRevision: store.suiteRevision
        )
        let staleRevision = first.revision
        // Advance the suite revision with an unrelated attachment.
        _ = try await store.importAttachment(
            id: UUID(),
            name: "other.txt",
            mediaType: "text/plain",
            data: Data("other".utf8),
            expectedRevision: store.suiteRevision
        )
        #expect(store.suiteRevision != staleRevision)

        // A retry of already-imported bytes stays idempotent even with a stale
        // revision, reporting the current revision (MCP maps this to
        // "duplicate"). See attachmentToolsAreBoundedAndNaturallyIdempotent.
        let duplicate = try await store.importAttachment(
            id: id,
            name: "reference.txt",
            mediaType: "text/plain",
            data: data,
            expectedRevision: staleRevision
        )
        #expect(duplicate.duplicate)
        #expect(duplicate.attachment == first.attachment)
        #expect(duplicate.revision == store.suiteRevision)
        #expect(store.suite.attachments.count == 2)
    }

    private func existingCatalog(
        legacySuiteID: UUID
    ) -> (
        catalog: EvaluationWorkspaceCatalog,
        legacyProjectID: UUID
    ) {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let selectedProjectID = UUID(uuidString: "00000000-0000-0000-0000-000000000411")!
        let selectedSuiteID = UUID(uuidString: "00000000-0000-0000-0000-000000000412")!
        let legacyProjectID = UUID(uuidString: "00000000-0000-0000-0000-000000000413")!
        let selectedProject = EvaluationProject(
            id: selectedProjectID,
            name: "Selected project",
            createdAt: date,
            updatedAt: date,
            archivedAt: nil,
            repository: nil,
            selectedSuiteID: selectedSuiteID,
            suites: [EvaluationSuiteRecord(
                id: selectedSuiteID,
                name: "Selected suite",
                createdAt: date,
                updatedAt: date,
                archivedAt: nil,
                repositoryDefinitionPath: nil,
                lastRepositoryRevision: nil
            )]
        )
        let legacyProject = EvaluationProject(
            id: legacyProjectID,
            name: "Legacy project",
            createdAt: date,
            updatedAt: date,
            archivedAt: nil,
            repository: nil,
            selectedSuiteID: legacySuiteID,
            suites: [EvaluationSuiteRecord(
                id: legacySuiteID,
                name: "Legacy suite",
                createdAt: date,
                updatedAt: date,
                archivedAt: nil,
                repositoryDefinitionPath: nil,
                lastRepositoryRevision: nil
            )]
        )
        return (
            EvaluationWorkspaceCatalog(
                selectedProjectID: selectedProjectID,
                projects: [selectedProject, legacyProject],
                migratedLegacyStorageAt: nil
            ),
            legacyProjectID
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EvaluationWorkspaceRepairTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
