import Foundation
import Testing
@testable import FoundationEvals

struct EvaluationWorkspaceStateMigrationTests {
    @Test func legacyStateIsCopiedAndDecodedWithoutLosingLocalEvidence() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = EvaluationSuite()
        let state = try representativeState(for: suite)
        let data = try writeLegacy(suite: suite, state: state, to: directory)
        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
        let target = suiteDirectory(in: directory, catalog: bootstrap.catalog, suiteID: suite.id)

        #expect(try Data(contentsOf: target.appending(path: "state.json")) == data)
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == data)
        #expect(EvaluationWorkspacePersistence.hasCompletedLegacyStateMigration(in: target))
        let loaded = EvaluationWorkspaceStatePersistence.loadSuiteLocalState(from: target.appending(path: "state.json"))
        #expect(loaded.notice == nil)
        #expect(loaded.state.baselineApprovals.map(\.id) == state.baselineApprovals.map(\.id))
        #expect(loaded.state.humanCorrections.map(\.id) == state.humanCorrections.map(\.id))
        #expect(loaded.state.reviewedJudgeExamples.map(\.id) == state.reviewedJudgeExamples.map(\.id))
        #expect(loaded.state.experiments.map(\.id) == state.experiments.map(\.id))
    }

    @Test func existingCatalogRepairsMatchingNonselectedSuiteStateWithoutRestoringAuthority() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = EvaluationSuite()
        let state = try representativeState(for: suite)
        let data = try writeLegacy(suite: suite, state: state, to: directory)
        let catalog = existingCatalog(legacySuite: suite)
        try EvaluationWorkspacePersistence.save(catalog, in: directory)
        let target = suiteDirectory(in: directory, catalog: catalog, suiteID: suite.id)
        try EvaluationWorkspacePersistence.createSuiteDirectories(at: target)
        try CanonicalJSON.data(for: suite).write(to: target.appending(path: "suite.json"))

        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
        let loaded = EvaluationWorkspaceStatePersistence.loadSuiteLocalState(from: target.appending(path: "state.json"))
        #expect(bootstrap.catalog.selectedProjectID == catalog.selectedProjectID)
        #expect(bootstrap.catalog.projects.first?.selectedSuiteID == catalog.projects.first?.selectedSuiteID)
        #expect(bootstrap.catalog.migratedLegacyStorageAt != nil)
        #expect(bootstrap.notice?.contains("fresh review") == true)
        #expect(loaded.state.baselineApprovals.map(\.id) == state.baselineApprovals.map(\.id))
        #expect(loaded.state.baselineApprovals.allSatisfy { !$0.isCurrent })
        #expect(loaded.state.humanCorrections.isEmpty)
        #expect(loaded.state.reviewedJudgeExamples.isEmpty)
        #expect(loaded.state.experiments.map(\.id) == state.experiments.map(\.id))
        #expect(loaded.state.experiments.allSatisfy { $0.decision == .inconclusive })
        let archives = try FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("state-recovered-legacy-") }
        let archive = try #require(archives.first)
        #expect(archives.count == 1)
        #expect(try Data(contentsOf: archive) == data)
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == data)

        let repeated = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
        #expect(repeated.notice == nil)
        #expect(repeated.catalog == bootstrap.catalog)
        #expect(try CanonicalJSON.decode(EvaluationWorkspaceCatalog.self, from:
            Data(contentsOf: directory.appending(path: EvaluationWorkspacePersistence.catalogFilename))) == repeated.catalog)
    }

    @Test func existingDestinationStateWinsAndRepeatedBootstrapIsIdempotent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = EvaluationSuite()
        let original = try representativeState(for: suite)
        let legacyData = try writeLegacy(suite: suite, state: original, to: directory)
        let catalog = existingCatalog(legacySuite: suite)
        try EvaluationWorkspacePersistence.save(catalog, in: directory)
        let target = suiteDirectory(in: directory, catalog: catalog, suiteID: suite.id)
        try EvaluationWorkspacePersistence.createSuiteDirectories(at: target)
        var current = original
        current.baselineApprovals[0].revokedAt = Date()
        current.baselineApprovals[0].note = "Current destination wins"
        let currentData = try CanonicalJSON.data(for: current)
        try currentData.write(to: target.appending(path: "state.json"))

        for _ in 0..<2 {
            let bootstrap = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
            #expect(bootstrap.notice == nil)
            #expect(bootstrap.catalog == catalog)
            #expect(try Data(contentsOf: target.appending(path: "state.json")) == currentData)
            #expect(try Data(contentsOf: directory.appending(path: "state.json")) == legacyData)
        }
        #expect(EvaluationWorkspacePersistence.hasCompletedLegacyStateMigration(in: target))
        // Adopting a valid old workspace must also close future import.
        try FileManager.default.removeItem(at: target.appending(path: "state.json"))
        _ = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "state.json").path))
    }

    @Test func missingCatalogSuiteIDDoesNotCopyLegacyStateIntoSelectedSuite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = EvaluationSuite()
        let data = try writeLegacy(suite: legacy, state: representativeState(for: legacy), to: directory)
        let other = EvaluationSuite()
        let catalog = existingCatalog(legacySuite: other)
        try EvaluationWorkspacePersistence.save(catalog, in: directory)
        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: legacy)
        #expect(bootstrap.catalog == catalog)
        #expect(bootstrap.notice == nil)
        for project in catalog.projects {
            for record in project.suites {
                let target = EvaluationWorkspacePersistence.suiteDirectory(
                    supportDirectory: directory, projectID: project.id, suiteID: record.id)
                #expect(!FileManager.default.fileExists(atPath: target.appending(path: "state.json").path))
            }
        }
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == data)
    }

    @Test func corruptLegacyStateIsCopiedVerbatimAndPreserved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = EvaluationSuite()
        let corrupt = Data("{ not valid state".utf8)
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try corrupt.write(to: directory.appending(path: "state.json"))
        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
        let target = suiteDirectory(in: directory, catalog: bootstrap.catalog, suiteID: suite.id)
        #expect(try Data(contentsOf: target.appending(path: "state.json")) == corrupt)
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == corrupt)
        #expect(EvaluationWorkspaceStatePersistence.loadSuiteLocalState(from: target.appending(path: "state.json")).notice != nil)
    }

    @MainActor
    @Test(arguments: [false, true])
    func completedMigrationCannotReactivateRevokedApprovalsAfterRelaunch(missing: Bool) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var suite = EvaluationSuite()
        suite.scoringMode = .exactMatch
        suite.releasePolicy.requireApprovedBaseline = true
        let state = try representativeState(for: suite)
        let originalBytes = try writeLegacy(suite: suite, state: state, to: directory)
        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
        let target = suiteDirectory(in: directory, catalog: bootstrap.catalog, suiteID: suite.id)
        let stateURL = target.appending(path: "state.json")
        var revoked = state
        revoked.baselineApprovals[0].revokedAt = Date()
        try CanonicalJSON.data(for: revoked).write(to: stateURL, options: .atomic)
        if missing { try FileManager.default.removeItem(at: stateURL) }
        else { try Data("{ damaged current state".utf8).write(to: stateURL, options: .atomic) }

        let reloaded = EvaluationStore(supportDirectory: directory)
        #expect(reloaded.activeBaselineApproval == nil)
        let loaded = EvaluationWorkspaceStatePersistence.loadSuiteLocalState(from: stateURL)
        #expect(loaded.notice != nil)
        #expect(loaded.state.baselineApprovals.isEmpty)
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == originalBytes)
        if !missing {
            #expect(try Data(contentsOf: stateURL) == Data("{ damaged current state".utf8))
        }
        // A complete, otherwise compatible local-scored run cannot replace the
        // required approval. No model service or incomplete-run shortcut is used.
        let run = passingRun(suite: suite, runID: state.baselineApprovals[0].runID)
        let before = EvaluationReleaseCheckEvaluator.report(
            projectID: bootstrap.catalog.selectedProjectID, suite: suite, currentSuiteRevision: "fixture",
            run: run, baseline: run, approvedBaseline: state.baselineApprovals[0])
        #expect(before.outcome == .passed)
        let after = EvaluationReleaseCheckEvaluator.report(
            projectID: bootstrap.catalog.selectedProjectID, suite: suite, currentSuiteRevision: "fixture",
            run: run, baseline: run, approvedBaseline: reloaded.activeBaselineApproval)
        #expect(after.outcome == .incompleteOrIncompatibleEvidence)
        #expect(after.failures.contains { $0.contains("explicitly approved baseline") })
    }

    private func passingRun(suite: EvaluationSuite, runID: UUID) -> EvaluationRun {
        let results = suite.cases.map { item in
            EvaluationSampleResult(caseID: item.id, caseName: item.name, repetition: 1,
                prompt: item.prompt, effectivePrompt: item.prompt, expected: item.expected, response: item.expected,
                status: .passed, score: nil, rationale: "Exact match", durationMilliseconds: 1, usage: .init(),
                judgeDurationMilliseconds: nil, judgeUsage: nil, errorCategory: nil, errorMessage: nil,
                judgeErrorCategory: nil, judgeErrorMessage: nil)
        }
        return EvaluationRun(id: runID, suiteID: suite.id, suiteName: suite.name, suiteVersion: suite.version,
            instructions: suite.instructions, criteria: suite.criteria, scoringMode: suite.scoringMode, repetitions: 1,
            judgePromptVersion: nil, judgePassingScore: nil, plannedSampleCount: results.count,
            suiteRevision: "fixture", plannedCases: suite.cases, startedAt: Date(), completedAt: Date(),
            cancelled: false, terminationReason: nil,
            environment: .init(operatingSystem: "fixture", locale: "en", model: "fixture", modelContextSize: 4096),
            attachments: [], results: results)
    }

    private func existingCatalog(legacySuite: EvaluationSuite) -> EvaluationWorkspaceCatalog {
        let now = Date()
        func project(suite: EvaluationSuite) -> EvaluationProject {
            .init(id: UUID(), name: "Project", createdAt: now, updatedAt: now, archivedAt: nil,
                repository: nil, selectedSuiteID: suite.id,
                suites: [.init(id: suite.id, name: suite.name, createdAt: now, updatedAt: now,
                    archivedAt: nil, repositoryDefinitionPath: nil, lastRepositoryRevision: nil)])
        }
        let selected = project(suite: EvaluationSuite())
        return .init(selectedProjectID: selected.id, projects: [selected, project(suite: legacySuite)], migratedLegacyStorageAt: nil)
    }

    private func suiteDirectory(in directory: URL, catalog: EvaluationWorkspaceCatalog, suiteID: UUID) -> URL {
        let project = catalog.projects.first { $0.suites.contains { $0.id == suiteID } }!
        return EvaluationWorkspacePersistence.suiteDirectory(supportDirectory: directory, projectID: project.id, suiteID: suiteID)
    }

    @discardableResult
    private func writeLegacy(suite: EvaluationSuite, state: EvaluationSuiteLocalState, to directory: URL) throws -> Data {
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        let data = try CanonicalJSON.data(for: state)
        try data.write(to: directory.appending(path: "state.json"))
        return data
    }

    private func representativeState(for suite: EvaluationSuite) throws -> EvaluationSuiteLocalState {
        let runID = UUID(), assessmentID = UUID(), sampleID = UUID()
        let contract = try EvaluationScoringContract(suite: suite)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var state = EvaluationSuiteLocalState()
        state.baselineApprovals = [.init(id: UUID(), runID: runID, assessmentID: nil,
            suiteRevision: "fixture", approvedAt: date, note: "Historical approval", revokedAt: nil, scoringContract: contract)]
        state.humanCorrections = [.init(id: UUID(), runID: runID, assessmentID: assessmentID, sampleID: sampleID,
            originalStatus: .failed, originalScore: 2, correctedStatus: .passed, correctedScore: 4,
            reason: "Historical review", reviewer: "fixture", createdAt: date)]
        state.reviewedJudgeExamples = [.init(id: UUID(), sourceRunID: runID, sourceAssessmentID: assessmentID,
            sampleID: sampleID, expectedStatus: .passed, reason: "Historical example", createdAt: date,
            scoringContract: contract, subjectEvidenceDigest: "fixture")]
        state.experiments = [.init(id: UUID(), name: "Historical experiment", createdAt: date,
            suiteRevision: "fixture", casesDigest: "cases", scoringDigest: "scoring", judgeDigest: "judge",
            current: .init(id: UUID(), name: "Current", instructions: "Current"),
            candidate: .init(id: UUID(), name: "Candidate", instructions: "Candidate"),
            executionOrder: [suite.cases[0].id], runIDs: [runID], decision: .adoptCandidate)]
        return state
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "StateMigration-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
