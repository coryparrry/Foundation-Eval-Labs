import CryptoKit
import Foundation
import Testing
@testable import FoundationEvals

@MainActor
struct EvaluationWorkspaceRepairTests {
    @Test func failedBackupPreservesUnreadableDestinationAndLegacy() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let catalog = try fixture.installOldCatalog()
        let target = fixture.target(in: catalog)
        let stateURL = target.appending(path: "state.json")
        let corrupt = Data("{ unreadable current state".utf8)
        try corrupt.write(to: stateURL)
        let digest = SHA256.hash(data: corrupt).map { String(format: "%02x", $0) }.joined()
        // A conflicting archive must not be mistaken for successful preservation.
        let archive = target.appending(path: "state-unreadable-\(digest).json")
        try Data("wrong backup".utf8).write(to: archive)
        let result = try fixture.bootstrap()
        #expect(result.notice?.contains("could not be recovered") == true)
        #expect(try Data(contentsOf: stateURL) == corrupt)
        #expect(try Data(contentsOf: archive) == Data("wrong backup".utf8))
        #expect(try Data(contentsOf: fixture.legacyURL) == fixture.legacyData)
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: EvaluationWorkspacePersistence.stateMigrationMarkerFilename).path))
        try FileManager.default.removeItem(at: archive)
        #expect(try fixture.bootstrap().notice?.contains("quarantined") == true)
        let recovered = EvaluationWorkspaceStatePersistence.loadSuiteLocalState(from: stateURL).state
        #expect(recovered.baselineApprovals.allSatisfy { !$0.isCurrent })
        #expect(try Data(contentsOf: archive) == corrupt)
    }

    @Test func validDestinationIsPreserved() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let catalog = try fixture.installOldCatalog()
        let target = fixture.target(in: catalog)
        let data = try CanonicalJSON.data(for: EvaluationSuiteLocalState())
        try data.write(to: target.appending(path: "state.json"))
        #expect(try fixture.bootstrap().notice == nil)
        #expect(try Data(contentsOf: target.appending(path: "state.json")) == data)
    }

    @Test func corruptDestinationWithoutLegacyIsPreserved() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let catalog = try fixture.installOldCatalog()
        let target = fixture.target(in: catalog)
        let corrupt = Data("{ not valid state".utf8)
        try corrupt.write(to: target.appending(path: "state.json"))
        try FileManager.default.removeItem(at: fixture.legacyURL)
        #expect(try fixture.bootstrap().notice == nil)
        #expect(try Data(contentsOf: target.appending(path: "state.json")) == corrupt)
    }

    @Test func corruptDestinationIsRecoveredWithoutRestoringApprovalAuthority() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let catalog = try fixture.installOldCatalog()
        let target = fixture.target(in: catalog)
        let corrupt = Data("{ not valid state".utf8)
        try corrupt.write(to: target.appending(path: "state.json"))
        let result = try fixture.bootstrap()
        #expect(result.notice?.contains("quarantined") == true)
        #expect(result.catalog.migratedLegacyStorageAt != nil)
        let recovered = EvaluationWorkspaceStatePersistence.loadSuiteLocalState(from: target.appending(path: "state.json")).state
        #expect(recovered.baselineApprovals.allSatisfy { !$0.isCurrent })
        #expect(recovered.humanCorrections.isEmpty)
        #expect(recovered.reviewedJudgeExamples.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: target.path)
        let backup = try #require(files.first { $0.hasPrefix("state-unreadable-") })
        #expect(try Data(contentsOf: target.appending(path: backup)) == corrupt)
        let legacy = try #require(files.first { $0.hasPrefix("state-recovered-legacy-") })
        #expect(try Data(contentsOf: target.appending(path: legacy)) == fixture.legacyData)
        #expect(try fixture.bootstrap().notice == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).sorted() == files.sorted())
    }

    @Test func corruptDestinationWithCorruptLegacyIsLeftForLoadNotice() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let catalog = try fixture.installOldCatalog()
        let target = fixture.target(in: catalog)
        let corrupt = Data("{ corrupt destination".utf8)
        try corrupt.write(to: target.appending(path: "state.json"))
        try Data("{ corrupt legacy".utf8).write(to: fixture.legacyURL, options: .atomic)
        let result = try fixture.bootstrap()
        #expect(result.notice == nil)
        #expect(result.catalog.migratedLegacyStorageAt == nil)
        #expect(try Data(contentsOf: target.appending(path: "state.json")) == corrupt)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).filter { $0.hasPrefix("state-unreadable-") }.isEmpty)
    }

    @Test func duplicateImportWithStaleRevisionStaysIdempotent() async throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let store = EvaluationStore(supportDirectory: fixture.directory)
        let id = UUID()
        let data = Data("duplicate reference".utf8)
        let first = try await store.importAttachment(id: id, name: "reference.txt", mediaType: "text/plain",
            data: data, expectedRevision: store.suiteRevision)
        let staleRevision = first.revision
        _ = try await store.importAttachment(id: UUID(), name: "other.txt", mediaType: "text/plain",
            data: Data("other".utf8), expectedRevision: store.suiteRevision)
        #expect(store.suiteRevision != staleRevision)
        let duplicate = try await store.importAttachment(id: id, name: "reference.txt", mediaType: "text/plain",
            data: data, expectedRevision: staleRevision)
        #expect(duplicate.duplicate)
        #expect(duplicate.attachment == first.attachment)
        #expect(duplicate.revision == store.suiteRevision)
        #expect(store.suite.attachments.count == 2)
    }
}
