import Foundation
import Testing
@testable import FoundationEvals

@MainActor
struct EvaluationWorkspaceRepairTests {
    @Test(arguments: [false, true])
    func completedMigrationNeverRestoresARevokedApproval(missing: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = EvaluationSuite()
        let legacy = try approvedState(for: suite)
        let legacyData = try CanonicalJSON.data(for: legacy)
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try legacyData.write(to: directory.appending(path: "state.json"))

        let initial = EvaluationStore(supportDirectory: directory)
        #expect(initial.activeBaselineApproval?.id == legacy.baselineApprovals[0].id)
        let target = suiteDirectory(store: initial, support: directory)
        #expect(EvaluationWorkspacePersistence.legacyStateWasMigrated(in: target))
        let stateURL = target.appending(path: "state.json")
        var revoked = legacy
        revoked.baselineApprovals[0].revokedAt = Date()
        try CanonicalJSON.data(for: revoked).write(to: stateURL, options: .atomic)
        #expect(EvaluationStore(supportDirectory: directory).activeBaselineApproval == nil)

        let damaged = Data("{ newer state was damaged".utf8)
        if missing { try FileManager.default.removeItem(at: stateURL) }
        else { try damaged.write(to: stateURL, options: .atomic) }

        for _ in 0..<2 {
            let reloaded = EvaluationStore(supportDirectory: directory)
            #expect(reloaded.activeBaselineApproval == nil)
            #expect(reloaded.suiteLocalState.humanCorrections.isEmpty)
            #expect(reloaded.notice != nil)
            #expect(reloaded.selectedSuiteID == initial.selectedSuiteID)
            #expect(reloaded.selectedProjectID == initial.selectedProjectID)
            if missing { #expect(!FileManager.default.fileExists(atPath: stateURL.path)) }
            else { #expect(try Data(contentsOf: stateURL) == damaged) }
        }
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == legacyData)
    }

    @Test(arguments: [false, true])
    func damagedExistingStateIsNeverReplacedEvenWithoutAMigrationMarker(corruptLegacy: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = EvaluationSuite()
        let legacy = corruptLegacy ? Data("{ legacy damaged".utf8)
            : try CanonicalJSON.data(for: approvedState(for: suite))
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try legacy.write(to: directory.appending(path: "state.json"))
        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
        let target = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory, projectID: bootstrap.catalog.selectedProjectID, suiteID: suite.id
        )
        try FileManager.default.removeItem(at: target.appending(path: EvaluationWorkspacePersistence.legacyStateMigrationFilename))
        let damaged = Data("{ current state contains later decisions".utf8)
        let stateURL = target.appending(path: "state.json")
        try damaged.write(to: stateURL, options: .atomic)

        _ = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
        let loaded = EvaluationWorkspaceStatePersistence.loadSuiteLocalState(from: stateURL)
        #expect(loaded.notice != nil)
        #expect(loaded.state.baselineApprovals.isEmpty)
        #expect(try Data(contentsOf: stateURL) == damaged)
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == legacy)
        let backups = try FileManager.default.contentsOfDirectory(atPath: target.path)
            .filter { $0.hasPrefix("state-unreadable-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: target.appending(path: #require(backups.first))) == damaged)
    }

    @Test func omittedFirstMigrationRecoversBytesWithoutRestoringAuthority() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = EvaluationSuite()
        let legacy = try approvedState(for: suite)
        let legacyData = try CanonicalJSON.data(for: legacy)
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try legacyData.write(to: directory.appending(path: "state.json"))
        let initial = EvaluationStore(supportDirectory: directory)
        let target = suiteDirectory(store: initial, support: directory)
        let stateURL = target.appending(path: "state.json")
        // Simulate a workspace created by an older version that omitted state.json.
        try FileManager.default.removeItem(at: stateURL)
        try FileManager.default.removeItem(at: target.appending(path: EvaluationWorkspacePersistence.legacyStateMigrationFilename))

        for _ in 0..<2 {
            let reloaded = EvaluationStore(supportDirectory: directory)
            #expect(reloaded.selectedSuiteID == initial.selectedSuiteID)
            #expect(reloaded.activeBaselineApproval == nil)
            #expect(reloaded.suiteLocalState.reviewedJudgeExamples.isEmpty)
            #expect(reloaded.notice?.contains("quarantined") == true)
            #expect(try Data(contentsOf: stateURL) == legacyData)
        }
        let recovery = EvaluationWorkspacePersistence.legacyStateRecoveryURL(for: legacyData, in: target)
        #expect(try Data(contentsOf: recovery) == legacyData)

        // Independently reviewed decisions are writable without promoting the old snapshot.
        var reviewed = EvaluationSuiteLocalState()
        var approval = legacy.baselineApprovals[0]
        approval.id = UUID()
        approval.approvedAt = Date()
        approval.note = "Independently reviewed after recovery"
        reviewed.baselineApprovals = [approval]
        try CanonicalJSON.data(for: reviewed).write(to: stateURL, options: .atomic)
        let loaded = EvaluationWorkspaceStatePersistence.loadSuiteLocalState(from: stateURL)
        #expect(loaded.notice == nil)
        #expect(loaded.state.baselineApprovals.first?.id == approval.id)
        #expect(try Data(contentsOf: recovery) == legacyData)
    }

    @Test func readOnlyRecoveryInspectionDoesNotWriteFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try CanonicalJSON.data(for: approvedState(for: EvaluationSuite()))
        let stateURL = directory.appending(path: "state.json")
        try data.write(to: stateURL)
        try data.write(to: EvaluationWorkspacePersistence.legacyStateRecoveryURL(for: data, in: directory))
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let loaded = EvaluationWorkspaceStatePersistence.loadSuiteLocalState(
            from: stateURL, preserveUnreadable: false
        )
        #expect(loaded.notice != nil)
        #expect(loaded.state.baselineApprovals.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == before)
        #expect(try Data(contentsOf: stateURL) == data)
    }

    @Test func duplicateImportWithStaleRevisionStaysIdempotent() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let id = UUID()
        let data = Data("duplicate reference".utf8)
        let first = try await store.importAttachment(
            id: id, name: "reference.txt", mediaType: "text/plain", data: data,
            expectedRevision: store.suiteRevision
        )
        let staleRevision = first.revision
        _ = try await store.importAttachment(
            id: UUID(), name: "other.txt", mediaType: "text/plain", data: Data("other".utf8),
            expectedRevision: store.suiteRevision
        )
        #expect(store.suiteRevision != staleRevision)
        let duplicate = try await store.importAttachment(
            id: id, name: "reference.txt", mediaType: "text/plain", data: data,
            expectedRevision: staleRevision
        )
        #expect(duplicate.duplicate)
        #expect(duplicate.attachment == first.attachment)
        #expect(duplicate.revision == store.suiteRevision)
        #expect(store.suite.attachments.count == 2)
    }

    private func approvedState(for suite: EvaluationSuite) throws -> EvaluationSuiteLocalState {
        var state = EvaluationSuiteLocalState()
        state.baselineApprovals = [.init(
            id: UUID(), runID: UUID(), assessmentID: nil, suiteRevision: "legacy",
            approvedAt: Date(timeIntervalSince1970: 1_700_000_000), note: "legacy approval",
            revokedAt: nil, scoringContract: try EvaluationScoringContract(suite: suite)
        )]
        return state
    }

    private func suiteDirectory(store: EvaluationStore, support: URL) -> URL {
        EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: support, projectID: store.selectedProjectID, suiteID: store.selectedSuiteID
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EvaluationWorkspaceRepairTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
