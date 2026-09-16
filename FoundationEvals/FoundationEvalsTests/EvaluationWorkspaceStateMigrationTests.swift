import Foundation
import Testing
@testable import FoundationEvals

struct EvaluationWorkspaceStateMigrationTests {
    @Test func legacyStateIsCopiedAndDecodedWithoutLosingLocalEvidence() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let bootstrap = try fixture.bootstrap()
        let target = fixture.target(in: bootstrap.catalog)
        let copied = try Data(contentsOf: target.appending(path: "state.json"))
        let state = try CanonicalJSON.decode(EvaluationSuiteLocalState.self, from: copied)
        #expect(copied == fixture.legacyData)
        #expect(state.baselineApprovals.map(\.id) == fixture.state.baselineApprovals.map(\.id))
        #expect(state.humanCorrections.map(\.id) == fixture.state.humanCorrections.map(\.id))
        #expect(state.reviewedJudgeExamples.map(\.id) == fixture.state.reviewedJudgeExamples.map(\.id))
        #expect(state.experiments.map(\.id) == fixture.state.experiments.map(\.id))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: EvaluationWorkspacePersistence.stateMigrationMarkerFilename).path))
        #expect(try Data(contentsOf: fixture.legacyURL) == fixture.legacyData)
    }

    @Test func existingCatalogRecoversMatchingNonselectedSuiteWithoutApprovalAuthority() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let catalog = try fixture.installOldCatalog()
        let target = fixture.target(in: catalog)
        let bootstrap = try fixture.bootstrap()
        let restored = try CanonicalJSON.decode(
            EvaluationSuiteLocalState.self, from: Data(contentsOf: target.appending(path: "state.json"))
        )
        #expect(bootstrap.catalog.selectedProjectID == catalog.selectedProjectID)
        #expect(bootstrap.catalog.projects.first?.selectedSuiteID == catalog.projects.first?.selectedSuiteID)
        #expect(bootstrap.notice?.contains("quarantined") == true)
        #expect(bootstrap.catalog.migratedLegacyStorageAt != nil)
        #expect(restored.baselineApprovals.map(\.id) == fixture.state.baselineApprovals.map(\.id))
        #expect(restored.baselineApprovals.allSatisfy { !$0.isCurrent })
        #expect(restored.humanCorrections.isEmpty)
        #expect(restored.reviewedJudgeExamples.isEmpty)
        #expect(restored.experiments.map(\.id) == fixture.state.experiments.map(\.id))
        let archive = try #require(FileManager.default.contentsOfDirectory(atPath: target.path)
            .first { $0.hasPrefix("state-recovered-legacy-") })
        #expect(try Data(contentsOf: target.appending(path: archive)) == fixture.legacyData)
        #expect(try Data(contentsOf: fixture.legacyURL) == fixture.legacyData)
        let persisted = try CanonicalJSON.decode(EvaluationWorkspaceCatalog.self,
            from: Data(contentsOf: fixture.directory.appending(path: EvaluationWorkspacePersistence.catalogFilename)))
        #expect(persisted == bootstrap.catalog)
        let repeated = try fixture.bootstrap()
        #expect(repeated.notice == nil)
        #expect(repeated.catalog == bootstrap.catalog)
    }

    @Test func existingDestinationStateWinsAndRepeatedBootstrapIsIdempotent() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let catalog = try fixture.installOldCatalog()
        let target = fixture.target(in: catalog)
        var destination = fixture.state
        destination.baselineApprovals[0].note = "destination wins"
        let data = try CanonicalJSON.data(for: destination)
        try data.write(to: target.appending(path: "state.json"), options: .atomic)
        let first = try fixture.bootstrap()
        let second = try fixture.bootstrap()
        #expect(first.notice == nil)
        #expect(second.notice == nil)
        #expect(second.catalog == catalog)
        #expect(try Data(contentsOf: target.appending(path: "state.json")) == data)
        #expect(try Data(contentsOf: fixture.legacyURL) == fixture.legacyData)
    }

    @Test func missingCatalogSuiteIDDoesNotCopyLegacyStateIntoSelectedSuite() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let catalog = try fixture.installOldCatalog(includeMatchingSuite: false)
        let selected = try #require(catalog.projects.first)
        let target = EvaluationWorkspacePersistence.suiteDirectory(supportDirectory: fixture.directory,
            projectID: selected.id, suiteID: selected.selectedSuiteID)
        let result = try fixture.bootstrap()
        #expect(result.notice == nil)
        #expect(result.catalog == catalog)
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "state.json").path))
        #expect(try Data(contentsOf: fixture.legacyURL) == fixture.legacyData)
    }

    @Test func corruptLegacyStateIsCopiedVerbatimAndPreserved() throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let corrupt = Data("{ not valid state".utf8)
        try corrupt.write(to: fixture.legacyURL, options: .atomic)
        let result = try fixture.bootstrap()
        #expect(try Data(contentsOf: fixture.target(in: result.catalog).appending(path: "state.json")) == corrupt)
        #expect(try Data(contentsOf: fixture.legacyURL) == corrupt)
    }

    @Test(arguments: [false, true])
    func completedMigrationNeverReplaysLegacyAfterStateLoss(deleted: Bool) throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let first = try fixture.bootstrap()
        let target = fixture.target(in: first.catalog)
        let stateURL = target.appending(path: "state.json")
        var current = fixture.state
        current.baselineApprovals[0].revokedAt = Date()
        current.humanCorrections = []
        current.reviewedJudgeExamples = []
        try CanonicalJSON.data(for: current).write(to: stateURL, options: .atomic)
        let corrupt = Data("{ damaged after revocation".utf8)
        if deleted { try FileManager.default.removeItem(at: stateURL) }
        else { try corrupt.write(to: stateURL, options: .atomic) }
        for _ in 0..<2 {
            let result = try fixture.bootstrap()
            #expect(result.notice?.contains("old approvals were not restored") == true)
            let loaded = EvaluationWorkspaceStatePersistence.loadSuiteLocalState(from: stateURL)
            #expect(loaded.state.baselineApprovals.isEmpty)
            #expect(loaded.state.humanCorrections.isEmpty)
            #expect(loaded.state.reviewedJudgeExamples.isEmpty)
            if deleted { #expect(!FileManager.default.fileExists(atPath: stateURL.path)) }
            else { #expect(try Data(contentsOf: stateURL) == corrupt) }
        }
        #expect(try Data(contentsOf: fixture.legacyURL) == fixture.legacyData)
    }

    @MainActor
    @Test(arguments: [false, true])
    func storeRelaunchDoesNotRestoreRevokedAuthority(deleted: Bool) throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let first = try fixture.bootstrap()
        let target = fixture.target(in: first.catalog)
        let stateURL = target.appending(path: "state.json")
        var revoked = fixture.state
        revoked.baselineApprovals[0].revokedAt = Date()
        try CanonicalJSON.data(for: revoked).write(to: stateURL, options: .atomic)
        let before = EvaluationStore(supportDirectory: fixture.directory)
        #expect(before.suiteLocalState.baselineApprovals.allSatisfy { !$0.isCurrent })
        if deleted { try FileManager.default.removeItem(at: stateURL) }
        else { try Data("{ damaged".utf8).write(to: stateURL, options: .atomic) }
        let after = EvaluationStore(supportDirectory: fixture.directory)
        #expect(after.suiteLocalState.baselineApprovals.allSatisfy { !$0.isCurrent })
        #expect(after.suiteLocalState.humanCorrections.isEmpty)
        #expect(after.suiteLocalState.reviewedJudgeExamples.isEmpty)
        #expect(try Data(contentsOf: fixture.legacyURL) == fixture.legacyData)
    }

    @MainActor
    @Test(arguments: [false, true])
    func retainedPassingRunCannotRegainLegacyBaselineApproval(deleted: Bool) throws {
        let fixture = try WorkspaceRecoveryFixture()
        defer { fixture.cleanup() }
        let store = EvaluationStore(supportDirectory: fixture.directory)
        store.draftSuite.scoringMode = .exactMatch
        store.draftSuite.repetitions = 1
        store.draftSuite.releasePolicy.requireApprovedBaseline = true
        #expect(store.saveSuite())
        let now = Date()
        let results = store.suite.cases.map { item in
            EvaluationSampleResult(caseID: item.id, caseName: item.name, repetition: 1,
                prompt: item.prompt, expected: item.expected, response: item.expected,
                status: .passed, score: nil, rationale: nil, durationMilliseconds: 1, usage: .init(),
                judgeDurationMilliseconds: nil, judgeUsage: nil, errorCategory: nil, errorMessage: nil,
                judgeErrorCategory: nil, judgeErrorMessage: nil)
        }
        let run = EvaluationRun(id: UUID(), suiteID: store.suite.id, suiteName: store.suite.name,
            suiteVersion: store.suite.version, instructions: store.suite.instructions, criteria: store.suite.criteria,
            scoringMode: .exactMatch, repetitions: 1, judgePromptVersion: nil, judgePassingScore: nil,
            plannedSampleCount: results.count, suiteRevision: store.suiteRevision, plannedCases: store.suite.cases,
            startedAt: now, completedAt: now, cancelled: false, terminationReason: nil,
            environment: .init(operatingSystem: "Test", locale: "en", model: "Fixture", modelContextSize: 4096),
            attachments: [], results: results, suiteDefinition: .init(suite: store.suite))
        store.runs = [run]
        let target = EvaluationWorkspacePersistence.suiteDirectory(supportDirectory: fixture.directory,
            projectID: store.selectedProjectID, suiteID: store.selectedSuiteID)
        try CanonicalJSON.data(for: run).write(to: target.appending(path: "Runs/\(run.id.uuidString).json"))
        try store.approveBaseline(runID: run.id, assessmentID: nil)
        let approval = try #require(store.activeBaselineApproval)
        let passing = EvaluationReleaseCheckEvaluator.report(projectID: store.selectedProjectID,
            suite: store.suite, currentSuiteRevision: store.suiteRevision,
            run: run, baseline: run, approvedBaseline: approval)
        #expect(passing.outcome == .passed)
        // Leave a genuinely compatible, approved historical snapshot in legacy storage.
        try CanonicalJSON.data(for: store.suite).write(to: fixture.directory.appending(path: "suite.json"), options: .atomic)
        try CanonicalJSON.data(for: store.suiteLocalState).write(to: fixture.legacyURL, options: .atomic)
        let stateURL = target.appending(path: "state.json")
        var current = store.suiteLocalState
        for index in current.baselineApprovals.indices { current.baselineApprovals[index].revokedAt = now }
        try CanonicalJSON.data(for: current).write(to: stateURL, options: .atomic)
        let revokedStore = EvaluationStore(supportDirectory: fixture.directory)
        #expect(revokedStore.activeBaselineApproval == nil)
        if deleted { try FileManager.default.removeItem(at: stateURL) }
        else { try Data("{ corrupted after revocation".utf8).write(to: stateURL, options: .atomic) }
        let reloaded = EvaluationStore(supportDirectory: fixture.directory)
        let retained = try #require(reloaded.runs.first { $0.id == run.id })
        #expect(retained.passedCount == results.count)
        #expect(reloaded.activeBaselineApproval == nil)
        let blocked = EvaluationReleaseCheckEvaluator.report(projectID: reloaded.selectedProjectID,
            suite: reloaded.suite, currentSuiteRevision: reloaded.suiteRevision,
            run: retained, baseline: retained, approvedBaseline: reloaded.activeBaselineApproval)
        #expect(blocked.outcome == .incompleteOrIncompatibleEvidence)
    }
}

/// Shared disk fixture keeps recovery tests on the real bootstrap and loader paths.
struct WorkspaceRecoveryFixture {
    let directory: URL
    let suite: EvaluationSuite
    let state: EvaluationSuiteLocalState
    let legacyData: Data
    var legacyURL: URL { directory.appending(path: "state.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "WorkspaceRecovery-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = EvaluationSuite()
        let runID = UUID(), assessmentID = UUID(), sampleID = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let contract = try EvaluationScoringContract(suite: suite)
        var state = EvaluationSuiteLocalState()
        state.baselineApprovals = [.init(id: UUID(), runID: runID, assessmentID: assessmentID,
            suiteRevision: "legacy", approvedAt: date, note: "legacy approval", revokedAt: nil, scoringContract: contract)]
        state.humanCorrections = [.init(id: UUID(), runID: runID, assessmentID: assessmentID, sampleID: sampleID,
            originalStatus: .failed, originalScore: 2, correctedStatus: .passed, correctedScore: 4,
            reason: "Reviewed", reviewer: "fixture", createdAt: date)]
        state.reviewedJudgeExamples = [.init(id: UUID(), sourceRunID: runID, sourceAssessmentID: assessmentID,
            sampleID: sampleID, expectedStatus: .passed, reason: "Reviewed example", createdAt: date,
            scoringContract: contract, subjectEvidenceDigest: "evidence")]
        state.experiments = [.init(id: UUID(), name: "Preserved experiment", createdAt: date,
            suiteRevision: "legacy", casesDigest: "cases", scoringDigest: "scoring", judgeDigest: "judge",
            current: .init(id: UUID(), name: "Current", instructions: "Current"),
            candidate: .init(id: UUID(), name: "Candidate", instructions: "Candidate"),
            executionOrder: suite.cases.map(\.id), runIDs: [runID], decision: .collectMoreEvidence)]
        self.state = state
        legacyData = try CanonicalJSON.data(for: state)
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try legacyData.write(to: directory.appending(path: "state.json"))
    }

    func bootstrap() throws -> EvaluationWorkspaceBootstrap {
        try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
    }

    func target(in catalog: EvaluationWorkspaceCatalog) -> URL {
        let projectID = catalog.projects.first { $0.suites.contains { $0.id == suite.id } }!.id
        return EvaluationWorkspacePersistence.suiteDirectory(supportDirectory: directory, projectID: projectID, suiteID: suite.id)
    }

    func installOldCatalog(includeMatchingSuite: Bool = true) throws -> EvaluationWorkspaceCatalog {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        func project(suiteID: UUID) -> EvaluationProject {
            .init(id: UUID(), name: "Fixture", createdAt: date, updatedAt: date, archivedAt: nil,
                repository: nil, selectedSuiteID: suiteID, suites: [
                    .init(id: suiteID, name: "Fixture", createdAt: date, updatedAt: date,
                        archivedAt: nil, repositoryDefinitionPath: nil, lastRepositoryRevision: nil)
                ])
        }
        var projects = [project(suiteID: UUID())]
        if includeMatchingSuite { projects.append(project(suiteID: suite.id)) }
        let catalog = EvaluationWorkspaceCatalog(selectedProjectID: projects[0].id, projects: projects, migratedLegacyStorageAt: nil)
        try EvaluationWorkspacePersistence.save(catalog, in: directory)
        if includeMatchingSuite {
            let target = target(in: catalog)
            try EvaluationWorkspacePersistence.createSuiteDirectories(at: target)
            try CanonicalJSON.data(for: suite).write(to: target.appending(path: "suite.json"))
        }
        return catalog
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
