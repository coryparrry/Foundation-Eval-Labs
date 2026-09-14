import Foundation
import Testing
@testable import FoundationEvals

struct EvaluationWorkspaceStateMigrationTests {
    @Test func legacyStateIsCopiedAndDecodedWithoutLosingLocalEvidence() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var suite = EvaluationSuite()
        suite.id = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let state = try representativeState(for: suite, marker: "legacy")
        let suiteData = try CanonicalJSON.data(for: suite)
        let stateData = try CanonicalJSON.data(for: state)
        try suiteData.write(to: directory.appending(path: "suite.json"))
        try stateData.write(to: directory.appending(path: "state.json"))

        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: suite
        )
        let target = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory,
            projectID: bootstrap.catalog.selectedProjectID,
            suiteID: suite.id
        )
        let destinationStateURL = target.appending(path: "state.json")
        let copiedData = try Data(contentsOf: destinationStateURL)
        let reloaded = try CanonicalJSON.decode(
            EvaluationSuiteLocalState.self,
            from: copiedData
        )

        #expect(copiedData == stateData)
        #expect(reloaded.baselineApprovals.map(\.id) == state.baselineApprovals.map(\.id))
        #expect(reloaded.humanCorrections.map(\.id) == state.humanCorrections.map(\.id))
        #expect(reloaded.reviewedJudgeExamples.map(\.id) == state.reviewedJudgeExamples.map(\.id))
        #expect(reloaded.experiments.map(\.id) == state.experiments.map(\.id))
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == stateData)
    }

    @Test func existingCatalogRepairsMatchingNonselectedSuiteState() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var suite = EvaluationSuite()
        suite.id = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let state = try representativeState(for: suite, marker: "existing-catalog")
        let suiteData = try CanonicalJSON.data(for: suite)
        let stateData = try CanonicalJSON.data(for: state)
        try suiteData.write(to: directory.appending(path: "suite.json"))
        try stateData.write(to: directory.appending(path: "state.json"))

        let fixture = existingCatalog(legacySuiteID: suite.id, includeLegacySuite: true)
        try EvaluationWorkspacePersistence.save(fixture.catalog, in: directory)
        let target = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory,
            projectID: fixture.legacyProjectID,
            suiteID: suite.id
        )
        try EvaluationWorkspacePersistence.createSuiteDirectories(at: target)
        try suiteData.write(to: target.appending(path: "suite.json"))

        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: suite
        )
        let reloaded = try CanonicalJSON.decode(
            EvaluationSuiteLocalState.self,
            from: Data(contentsOf: target.appending(path: "state.json"))
        )

        #expect(bootstrap.catalog.selectedProjectID == fixture.catalog.selectedProjectID)
        #expect(bootstrap.catalog.projects.first?.selectedSuiteID == fixture.selectedSuiteID)
        #expect(bootstrap.notice != nil)
        #expect(bootstrap.catalog.migratedLegacyStorageAt != nil)
        #expect(try Data(contentsOf: target.appending(path: "state.json")) == stateData)
        #expect(reloaded.baselineApprovals.map(\.id) == state.baselineApprovals.map(\.id))
        #expect(reloaded.humanCorrections.map(\.id) == state.humanCorrections.map(\.id))
        #expect(reloaded.reviewedJudgeExamples.map(\.id) == state.reviewedJudgeExamples.map(\.id))
        #expect(reloaded.experiments.map(\.id) == state.experiments.map(\.id))
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == stateData)
        let persistedCatalog = try CanonicalJSON.decode(
            EvaluationWorkspaceCatalog.self,
            from: Data(contentsOf: directory.appending(path: EvaluationWorkspacePersistence.catalogFilename))
        )
        #expect(persistedCatalog == bootstrap.catalog)

        let repeatBootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: suite
        )
        #expect(repeatBootstrap.notice == nil)
        #expect(repeatBootstrap.catalog.migratedLegacyStorageAt == bootstrap.catalog.migratedLegacyStorageAt)
    }

    @Test func existingDestinationStateWinsAndRepeatedBootstrapIsIdempotent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var suite = EvaluationSuite()
        suite.id = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
        let legacyState = try representativeState(for: suite, marker: "legacy")
        let legacyStateData = try CanonicalJSON.data(for: legacyState)
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try legacyStateData.write(to: directory.appending(path: "state.json"))

        let fixture = existingCatalog(legacySuiteID: suite.id, includeLegacySuite: true)
        try EvaluationWorkspacePersistence.save(fixture.catalog, in: directory)
        let target = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory,
            projectID: fixture.legacyProjectID,
            suiteID: suite.id
        )
        try EvaluationWorkspacePersistence.createSuiteDirectories(at: target)
        let destinationStateURL = target.appending(path: "state.json")
        var destinationState = try representativeState(for: suite, marker: "destination")
        destinationState.baselineApprovals[0].note = "destination wins"
        let destinationStateData = try CanonicalJSON.data(for: destinationState)
        try destinationStateData.write(to: destinationStateURL, options: .atomic)

        var changedLegacyState = try representativeState(for: suite, marker: "legacy-replacement")
        changedLegacyState.baselineApprovals[0].note = "legacy must remain untouched"
        let changedLegacyStateData = try CanonicalJSON.data(for: changedLegacyState)
        try changedLegacyStateData.write(
            to: directory.appending(path: "state.json"),
            options: .atomic
        )

        let firstBootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: suite
        )
        let secondBootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: suite
        )

        #expect(secondBootstrap.catalog.selectedProjectID == firstBootstrap.catalog.selectedProjectID)
        #expect(firstBootstrap.notice == nil)
        #expect(secondBootstrap.notice == nil)
        #expect(secondBootstrap.catalog.migratedLegacyStorageAt == nil)
        #expect(try Data(contentsOf: destinationStateURL) == destinationStateData)
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == changedLegacyStateData)

        let reloaded = try CanonicalJSON.decode(
            EvaluationSuiteLocalState.self,
            from: Data(contentsOf: destinationStateURL)
        )
        #expect(reloaded.baselineApprovals.first?.note == "destination wins")
    }

    @Test func missingCatalogSuiteIDDoesNotCopyLegacyStateIntoSelectedSuite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var legacySuite = EvaluationSuite()
        legacySuite.id = UUID(uuidString: "00000000-0000-0000-0000-000000000113")!
        let stateData = try CanonicalJSON.data(
            for: representativeState(for: legacySuite, marker: "unmatched")
        )
        try CanonicalJSON.data(for: legacySuite).write(to: directory.appending(path: "suite.json"))
        try stateData.write(to: directory.appending(path: "state.json"))

        let fixture = existingCatalog(legacySuiteID: legacySuite.id, includeLegacySuite: false)
        try EvaluationWorkspacePersistence.save(fixture.catalog, in: directory)
        let selectedTarget = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory,
            projectID: fixture.catalog.selectedProjectID,
            suiteID: fixture.selectedSuiteID
        )
        try EvaluationWorkspacePersistence.createSuiteDirectories(at: selectedTarget)

        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: legacySuite
        )

        #expect(bootstrap.notice == nil)
        #expect(bootstrap.catalog == fixture.catalog)
        #expect(!FileManager.default.fileExists(atPath: selectedTarget.appending(path: "state.json").path))
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == stateData)
    }

    @Test func corruptLegacyStateIsCopiedVerbatimAndPreserved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var suite = EvaluationSuite()
        suite.id = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let corruptState = Data("{ not valid state".utf8)
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try corruptState.write(to: directory.appending(path: "state.json"))

        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(
            in: directory,
            legacySuite: suite
        )
        let target = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory,
            projectID: bootstrap.catalog.selectedProjectID,
            suiteID: suite.id
        )

        #expect(try Data(contentsOf: target.appending(path: "state.json")) == corruptState)
        #expect(try Data(contentsOf: directory.appending(path: "state.json")) == corruptState)
    }

    private func existingCatalog(
        legacySuiteID: UUID,
        includeLegacySuite: Bool
    ) -> (
        catalog: EvaluationWorkspaceCatalog,
        selectedSuiteID: UUID,
        legacyProjectID: UUID
    ) {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let selectedProjectID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let selectedSuiteID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let legacyProjectID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let selectedRecord = EvaluationSuiteRecord(
            id: selectedSuiteID,
            name: "Selected suite",
            createdAt: date,
            updatedAt: date,
            archivedAt: nil,
            repositoryDefinitionPath: nil,
            lastRepositoryRevision: nil
        )
        let selectedProject = EvaluationProject(
            id: selectedProjectID,
            name: "Selected project",
            createdAt: date,
            updatedAt: date,
            archivedAt: nil,
            repository: nil,
            selectedSuiteID: selectedSuiteID,
            suites: [selectedRecord]
        )
        var projects = [selectedProject]
        if includeLegacySuite {
            let legacyRecord = EvaluationSuiteRecord(
                id: legacySuiteID,
                name: "Legacy suite",
                createdAt: date,
                updatedAt: date,
                archivedAt: nil,
                repositoryDefinitionPath: nil,
                lastRepositoryRevision: nil
            )
            projects.append(EvaluationProject(
                id: legacyProjectID,
                name: "Legacy project",
                createdAt: date,
                updatedAt: date,
                archivedAt: nil,
                repository: nil,
                selectedSuiteID: legacySuiteID,
                suites: [legacyRecord]
            ))
        }
        return (
            EvaluationWorkspaceCatalog(
                selectedProjectID: selectedProjectID,
                projects: projects,
                migratedLegacyStorageAt: nil
            ),
            selectedSuiteID,
            legacyProjectID
        )
    }

    private func representativeState(
        for suite: EvaluationSuite,
        marker: String
    ) throws -> EvaluationSuiteLocalState {
        let runID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let assessmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let sampleID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
        let experimentID = UUID(uuidString: "00000000-0000-0000-0000-000000000204")!
        let contract = try EvaluationScoringContract(suite: suite)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        var state = EvaluationSuiteLocalState()
        state.baselineApprovals = [EvaluationBaselineApproval(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000205")!,
            runID: runID,
            assessmentID: assessmentID,
            suiteRevision: "revision-\(marker)",
            approvedAt: date,
            note: marker,
            revokedAt: nil,
            scoringContract: contract
        )]
        state.humanCorrections = [EvaluationHumanCorrection(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000206")!,
            runID: runID,
            assessmentID: assessmentID,
            sampleID: sampleID,
            originalStatus: .failed,
            originalScore: 2,
            correctedStatus: .passed,
            correctedScore: 4,
            reason: "Reviewed \(marker)",
            reviewer: "fixture-reviewer",
            createdAt: date
        )]
        state.reviewedJudgeExamples = [EvaluationReviewedJudgeExample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000207")!,
            sourceRunID: runID,
            sourceAssessmentID: assessmentID,
            sampleID: sampleID,
            expectedStatus: .passed,
            reason: "Keep as a \(marker) example",
            createdAt: date,
            scoringContract: contract,
            subjectEvidenceDigest: "evidence-\(marker)"
        )]
        state.experiments = [EvaluationExperiment(
            id: experimentID,
            name: "Experiment \(marker)",
            createdAt: date,
            suiteRevision: "revision-\(marker)",
            casesDigest: "cases-\(marker)",
            scoringDigest: "scoring-\(marker)",
            judgeDigest: "judge-\(marker)",
            current: EvaluationExperimentVariant(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000208")!,
                name: "Current",
                instructions: "Current \(marker)",
                suiteRevision: "revision-\(marker)"
            ),
            candidate: EvaluationExperimentVariant(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000209")!,
                name: "Candidate",
                instructions: "Candidate \(marker)",
                suiteRevision: "candidate-\(marker)"
            ),
            executionOrder: [suite.cases[0].id],
            runIDs: [runID],
            decision: .collectMoreEvidence
        )]
        return state
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EvaluationWorkspaceStateMigrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
