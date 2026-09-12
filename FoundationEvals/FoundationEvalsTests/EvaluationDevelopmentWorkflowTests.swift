import Foundation
import Testing
@testable import FoundationEvals

struct EvaluationDevelopmentWorkflowTests {
    @Test func legacyBootstrapCopiesWithoutRemovingOriginals() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = EvaluationSuite()
        try CanonicalJSON.data(for: suite).write(to: directory.appending(path: "suite.json"))
        try Data("draft-marker".utf8).write(to: directory.appending(path: "suite-draft.json"))
        try FileManager.default.createDirectory(at: directory.appending(path: "Attachments"), withIntermediateDirectories: true)
        try Data("private".utf8).write(to: directory.appending(path: "Attachments/reference.txt"))
        try FileManager.default.createDirectory(at: directory.appending(path: "Runs"), withIntermediateDirectories: true)
        try Data("run-marker".utf8).write(to: directory.appending(path: "Runs/run.json"))

        let bootstrap = try EvaluationWorkspacePersistence.bootstrap(in: directory, legacySuite: suite)
        let target = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory,
            projectID: bootstrap.catalog.selectedProjectID,
            suiteID: suite.id
        )

        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "suite.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "suite-draft.json").path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Attachments/reference.txt").path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Runs/run.json").path))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "suite.json").path))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "suite-draft.json").path))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "Attachments/reference.txt").path))
        #expect(FileManager.default.fileExists(atPath: target.appending(path: "Runs/run.json").path))
        #expect(bootstrap.notice?.contains("left unchanged") == true)
    }

    @MainActor
    @Test func projectsAndSuitesKeepIndependentDraftsAndStableIDs() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let originalProject = store.selectedProjectID
        let originalSuite = store.selectedSuiteID
        store.draftSuite.name = "Original suite"
        #expect(store.saveSuite())

        let secondSuite = try store.createSuite(name: "Second suite")
        store.draftSuite.instructions = "Second-only instructions"
        #expect(store.saveSuite())
        try store.switchSuite(id: originalSuite)
        #expect(store.draftSuite.name == "Original suite")
        #expect(store.draftSuite.instructions != "Second-only instructions")
        try store.switchSuite(id: secondSuite)
        #expect(store.draftSuite.instructions == "Second-only instructions")

        let secondProject = try store.createProject(name: "Second project", starter: .groundedAnswers)
        #expect(store.selectedProjectID == secondProject)
        #expect(store.selectedProjectID != originalProject)
        #expect(store.draftSuite.cases.count >= 3)
        try store.switchProject(id: originalProject)
        #expect(store.selectedSuiteID == secondSuite)

        let reloaded = EvaluationStore(supportDirectory: directory)
        #expect(reloaded.projects.map(\.id).contains(originalProject))
        #expect(reloaded.projects.map(\.id).contains(secondProject))
        #expect(reloaded.selectedProjectID == originalProject)
        #expect(reloaded.selectedSuiteID == secondSuite)
    }

    @MainActor
    @Test func failedWorkspaceSwitchRestoresTheOriginalSuiteAndSelection() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let originalProject = store.selectedProjectID
        let originalSuite = store.selectedSuiteID
        let originalName = store.suite.name
        let brokenSuite = try store.createSuite(name: "Broken target")
        try store.switchSuite(id: originalSuite)
        let brokenDirectory = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: directory, projectID: originalProject, suiteID: brokenSuite
        )
        try FileManager.default.removeItem(at: brokenDirectory.appending(path: "suite.json"))

        #expect(throws: EvaluationWorkspaceError.self) {
            try store.switchSuite(id: brokenSuite)
        }
        #expect(store.selectedProjectID == originalProject)
        #expect(store.selectedSuiteID == originalSuite)
        #expect(store.suite.id == originalSuite)
        #expect(store.suite.name == originalName)

        store.draftSuite.name = "Original remains writable"
        #expect(store.saveSuite())
        #expect(!FileManager.default.fileExists(atPath: brokenDirectory.appending(path: "suite.json").path))
    }

    @Test func csvAndJSONLinesImportMapPreviewAndRejectBadRows() throws {
        let csv = Data("title,input,want\nBlue,Why blue?,Rayleigh\nQuoted,\"a,b\",ok\n".utf8)
        let mapping = EvaluationCaseImportMapping(
            nameColumn: "title", promptColumn: "input", expectedColumn: "want"
        )
        let preview = try EvaluationCaseImporter.preview(data: csv, format: .csv, mapping: mapping)
        #expect(preview.rows.count == 2)
        #expect(preview.rows[1].prompt == "a,b")
        #expect(preview.canImport)

        let jsonl = Data("{\"name\":\"One\",\"prompt\":\"P\",\"expected\":\"E\"}\n{\"name\":\"Two\",\"prompt\":2}\n".utf8)
        let invalid = try EvaluationCaseImporter.preview(
            data: jsonl,
            format: .jsonLines,
            mapping: .init(nameColumn: "name", promptColumn: "prompt", expectedColumn: "expected")
        )
        #expect(!invalid.canImport)
        #expect(invalid.issues.contains { $0.line == 2 && $0.message.contains("must be a string") })

        #expect(throws: EvaluationCaseImportError.self) {
            _ = try EvaluationCaseImporter.columns(
                in: Data(count: EvaluationStore.maximumTextFileBytes + 1), format: .csv
            )
        }
    }

    @MainActor
    @Test func starterPacksAreCompleteRunnableAndUseRelevantScoring() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        for pack in EvaluationStarterPack.allCases {
            let suite = pack.makeSuite()
            #expect(suite.cases.count >= 3)
            #expect(suite.cases.allSatisfy { !$0.name.isEmpty && !$0.prompt.isEmpty })
            #expect(!suite.criteria.isEmpty)
            #expect(store.validationIssue(for: suite, includeModelReadiness: false) == nil)
        }
        #expect(EvaluationStarterPack.structuredExtraction.makeSuite().features.outputFields.isEmpty == false)
        #expect(EvaluationStarterPack.groundedAnswers.makeSuite().cases.allSatisfy { !$0.expected.isEmpty })
        #expect(EvaluationStarterPack.conversationBehaviour.makeSuite().cases.contains { !$0.conversation.setupTurns.isEmpty })
    }

    @Test func experimentAnalysisUsesDistinctCasesNotRepeatCount() {
        let cases = (0..<4).map { EvaluationCase(name: "Case \($0)", prompt: "P", expected: "E") }
        let current = makeRun(cases: cases, statuses: [
            [.failed, .failed, .failed], [.passed, .passed, .passed],
            [.failed, .passed, .failed], [.passed, .failed, .passed]
        ])
        let candidate = makeRun(cases: cases, statuses: [
            [.passed, .passed, .passed], [.failed, .failed, .failed],
            [.failed, .passed, .failed], [.passed, .failed, .passed]
        ])
        let summary = EvaluationExperimentAnalyzer.summarize(current: current, candidate: candidate)
        #expect(summary.distinctCaseCoverage == 4)
        #expect(summary.improvedCaseIDs.count == 1)
        #expect(summary.regressedCaseIDs.count == 1)
        #expect(summary.unchangedCaseIDs.count == 2)
        #expect(summary.suggestedDecision == .inconclusive)
        #expect(EvaluationExperimentAnalyzer.balancedOrder(
            currentID: cases[0].id, candidateID: cases[1].id, caseCount: 4, repetitions: 3
        ).count == 24)
    }

    @Test func releaseChecksFailClosedAndDistinguishRegressionFromExecution() {
        var suite = EvaluationSuite()
        suite.scoringMode = .exactMatch
        suite.releasePolicy.required = true
        suite.releasePolicy.criticalCaseIDs = [suite.cases[0].id]
        let projectID = UUID()
        var run = makeRun(cases: suite.cases, statuses: [[.passed]])
        run.suiteID = suite.id
        run.scoringMode = suite.scoringMode
        run.suiteRevision = "current"

        let passed = EvaluationReleaseCheckEvaluator.report(
            projectID: projectID, suite: suite, currentSuiteRevision: "current",
            run: run, baseline: nil, approvedBaseline: nil
        )
        #expect(passed.outcome == .passed)

        run.results[0].status = .failed
        let regression = EvaluationReleaseCheckEvaluator.report(
            projectID: projectID, suite: suite, currentSuiteRevision: "current",
            run: run, baseline: nil, approvedBaseline: nil
        )
        #expect(regression.outcome == .regression)

        run.results[0].errorCategory = "provider"
        let execution = EvaluationReleaseCheckEvaluator.report(
            projectID: projectID, suite: suite, currentSuiteRevision: "current",
            run: run, baseline: nil, approvedBaseline: nil
        )
        #expect(execution.outcome == .executionError)

        let stale = EvaluationReleaseCheckEvaluator.report(
            projectID: projectID, suite: suite, currentSuiteRevision: "changed",
            run: run, baseline: nil, approvedBaseline: nil
        )
        #expect(stale.outcome == .executionError)
        #expect(stale.failures.contains { $0.contains("stale") })

        suite.releasePolicy.requireApprovedBaseline = true
        run.results[0].errorCategory = nil
        run.results[0].status = .passed
        let staleApproval = EvaluationBaselineApproval(
            id: UUID(), runID: run.id, assessmentID: nil, suiteRevision: "previous",
            approvedAt: Date(), note: nil, revokedAt: nil
        )
        let staleBaseline = EvaluationReleaseCheckEvaluator.report(
            projectID: projectID, suite: suite, currentSuiteRevision: "current",
            run: run, baseline: run, approvedBaseline: staleApproval
        )
        #expect(staleBaseline.outcome == .incompleteOrIncompatibleEvidence)
        #expect(staleBaseline.failures.contains { $0.contains("no longer current") })
    }

    @Test func releaseChecksUseTheSelectedAssessmentForCriticalCases() {
        var suite = EvaluationSuite()
        suite.scoringMode = .modelJudge
        suite.releasePolicy.criticalCaseIDs = [suite.cases[0].id]
        var run = makeRun(cases: suite.cases, statuses: [[.passed]])
        run.suiteID = suite.id
        run.suiteRevision = "current"
        let sample = run.results[0]
        let assessment = EvaluationAssessment(
            id: UUID(), runID: run.id, createdAt: Date(), origin: .reassessment,
            judge: .init(
                mode: .connection, connectionID: UUID(), connectionName: "Fixture",
                endpointKind: .customCompatible, baseURL: "https://judge.example",
                requestedModelID: "judge-v1", reportedModelID: "judge-v1",
                provider: "fixture", providerOrder: []
            ),
            promptVersion: "test", rubric: suite.criteria, passingScore: 3,
            samples: [.init(
                id: UUID(), sampleID: sample.id, status: .failed, score: 2,
                rationale: "Incorrect", trace: nil, errorCategory: nil, errorMessage: nil,
                usage: nil, durationMilliseconds: 1
            )],
            totalUsage: nil, durationMilliseconds: 1,
            cost: .init(availability: .unavailable, usd: nil, explanation: "Fixture"),
            supersedesAssessmentID: nil
        )
        run.assessments = [assessment]
        run.selectedAssessmentID = assessment.id

        let report = EvaluationReleaseCheckEvaluator.report(
            projectID: UUID(), suite: suite, currentSuiteRevision: "current",
            run: run, baseline: nil, approvedBaseline: nil
        )

        #expect(report.outcome == .regression)
        #expect(report.assessmentID == assessment.id)

        var mixedRun = run
        var mixedAssessment = assessment
        var secondIdentity = assessment.judge
        secondIdentity.reportedModelID = "judge-v2"
        mixedAssessment.observedJudgeIdentities = [assessment.judge, secondIdentity]
        mixedRun.assessments = [mixedAssessment]
        let mixed = EvaluationReleaseCheckEvaluator.report(
            projectID: UUID(), suite: suite, currentSuiteRevision: "current",
            run: mixedRun, baseline: nil, approvedBaseline: nil
        )
        #expect(mixed.outcome == .incompleteOrIncompatibleEvidence)
        #expect(mixed.failures.contains { $0.contains("mixed judge") })
    }

    @Test func releaseChecksRejectMissingOrUnscoredJudgeAssessment() {
        var suite = EvaluationSuite()
        suite.scoringMode = .modelJudge
        var run = makeRun(cases: suite.cases, statuses: [[.passed]])
        run.suiteID = suite.id
        run.suiteRevision = "current"

        let missing = EvaluationReleaseCheckEvaluator.report(
            projectID: UUID(), suite: suite, currentSuiteRevision: "current",
            run: run, baseline: nil, approvedBaseline: nil
        )
        #expect(missing.outcome == .incompleteOrIncompatibleEvidence)
        #expect(missing.failures.contains { $0.contains("assessment") })
    }

    @Test func releaseChecksRejectUnscoredManualReviewRuns() {
        var suite = EvaluationSuite()
        suite.scoringMode = .review
        var run = makeRun(cases: suite.cases, statuses: [[.unscored]])
        run.suiteID = suite.id
        run.scoringMode = .review
        run.suiteRevision = "current"

        let report = EvaluationReleaseCheckEvaluator.report(
            projectID: UUID(), suite: suite, currentSuiteRevision: "current",
            run: run, baseline: nil, approvedBaseline: nil
        )

        #expect(report.outcome == .incompleteOrIncompatibleEvidence)
        #expect(report.failures.contains { $0.contains("pass/fail evidence") })
    }

    @MainActor
    @Test func releasePolicyRejectsFailOpenOrInvalidThresholds() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        var suite = store.suite

        suite.releasePolicy.maximumPassRateRegression = 1.01
        #expect(store.validationIssue(for: suite, includeModelReadiness: false)?.contains("between 0 and 1") == true)
        var run = makeRun(cases: suite.cases, statuses: [[.passed]])
        run.suiteID = suite.id
        run.suiteRevision = "current"
        let invalidReport = EvaluationReleaseCheckEvaluator.report(
            projectID: UUID(), suite: suite, currentSuiteRevision: "current",
            run: run, baseline: nil, approvedBaseline: nil
        )
        #expect(invalidReport.outcome == .incompleteOrIncompatibleEvidence)
        #expect(invalidReport.failures.contains { $0.contains("release policy is invalid") })
        suite.releasePolicy.maximumPassRateRegression = 0
        suite.releasePolicy.maximumErrorCount = -1
        #expect(store.validationIssue(for: suite, includeModelReadiness: false)?.contains("error limit") == true)
        suite.releasePolicy.maximumErrorCount = 0
        suite.releasePolicy.maximumAverageLatencyMilliseconds = .infinity
        #expect(store.validationIssue(for: suite, includeModelReadiness: false)?.contains("finite") == true)
        suite.releasePolicy.maximumAverageLatencyMilliseconds = nil
        suite.releasePolicy.criticalCaseIDs = [UUID()]
        #expect(store.validationIssue(for: suite, includeModelReadiness: false)?.contains("critical release case") == true)
    }

    @Test func releaseChecksKeepTheExplicitlyApprovedBaselineAssessment() {
        var suite = EvaluationSuite()
        suite.scoringMode = .modelJudge
        suite.releasePolicy.requireApprovedBaseline = true
        let suiteID = suite.id
        let judge = EvaluationJudgeIdentity(
            mode: .connection, connectionID: UUID(), connectionName: "Fixture",
            endpointKind: .customCompatible, baseURL: "https://judge.example",
            requestedModelID: "judge-v1", reportedModelID: "judge-v1",
            provider: "fixture", providerOrder: []
        )
        func assessment(for run: EvaluationRun, status: EvaluationResultStatus) -> EvaluationAssessment {
            EvaluationAssessment(
                id: UUID(), runID: run.id, createdAt: Date(), origin: .reassessment,
                judge: judge, promptVersion: "test", rubric: suite.criteria, passingScore: 3,
                samples: [.init(
                    id: UUID(), sampleID: run.results[0].id, status: status,
                    score: status == .passed ? 4 : 2, rationale: "Fixture", trace: nil,
                    errorCategory: nil, errorMessage: nil, usage: nil, durationMilliseconds: 1
                )],
                totalUsage: nil, durationMilliseconds: 1,
                cost: .init(availability: .unavailable, usd: nil, explanation: "Fixture"),
                supersedesAssessmentID: nil
            )
        }

        var baseline = makeRun(cases: suite.cases, statuses: [[.passed]])
        baseline.suiteID = suiteID
        baseline.suiteRevision = "current"
        let approvedAssessment = assessment(for: baseline, status: .passed)
        let laterAssessment = assessment(for: baseline, status: .failed)
        baseline.assessments = [approvedAssessment, laterAssessment]
        baseline.selectedAssessmentID = laterAssessment.id

        var current = makeRun(cases: suite.cases, statuses: [[.failed]])
        current.suiteID = suiteID
        current.suiteRevision = "current"
        let currentAssessment = assessment(for: current, status: .failed)
        current.assessments = [currentAssessment]
        current.selectedAssessmentID = currentAssessment.id
        let approval = EvaluationBaselineApproval(
            id: UUID(), runID: baseline.id, assessmentID: approvedAssessment.id,
            suiteRevision: "current", approvedAt: Date(), note: nil, revokedAt: nil
        )

        let report = EvaluationReleaseCheckEvaluator.report(
            projectID: UUID(), suite: suite, currentSuiteRevision: "current",
            run: current, baseline: baseline, approvedBaseline: approval
        )

        #expect(report.outcome == .regression)
        #expect(report.failures.contains { $0.contains("Pass rate regressed") })
    }

    @MainActor
    @Test func explicitUnknownReleaseRunDoesNotFallBackToLatestRun() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        var completed = makeRun(cases: store.suite.cases, statuses: [[.passed]])
        completed.suiteID = store.suite.id
        completed.suiteRevision = store.suiteRevision
        store.runs = [completed]

        let report = store.releaseCheckReport(runID: UUID())

        #expect(report.outcome == .incompleteOrIncompatibleEvidence)
        #expect(report.runID == nil)
        #expect(report.failures.contains { $0.contains("No completed run") || $0.contains("Run the suite") })
    }

    @Test func repositoryDefinitionsExcludeLocalJudgeBindings() {
        var suite = EvaluationSuite()
        let connectionID = UUID()
        let approvedAt = Date()
        let connection = EvaluationJudgeConnection(
            id: connectionID, name: "Fixture", kind: .localCompatible,
            baseURL: "http://127.0.0.1:11434/v1", modelID: "judge"
        )
        suite.judgeConfiguration = .init(
            mode: .connection, connectionID: connectionID,
            externalEvidenceApprovedAt: approvedAt, includeReferenceAttachments: false,
            approvedConnectionID: connectionID, approvedIncludeReferenceAttachments: false,
            approvedConnectionDigest: connection.disclosureDigest
        )

        let definition = EvaluationSuiteDefinition(suite: suite)
        #expect(definition.judgeConfiguration.mode == .connection)
        #expect(definition.judgeConfiguration.connectionID == nil)
        #expect(definition.judgeConfiguration.externalEvidenceApprovedAt == nil)
        #expect(definition.judgeConfiguration.approvedConnectionID == nil)
        #expect(definition.judgeConfiguration.approvedIncludeReferenceAttachments == nil)
        #expect(definition.judgeConfiguration.approvedConnectionDigest == nil)

        let reapplied = definition.applyingLocalState(from: suite)
        #expect(reapplied.judgeConfiguration.connectionID == connectionID)
        #expect(reapplied.judgeConfiguration.externalEvidenceApprovedAt == approvedAt)
        #expect(reapplied.judgeConfiguration.includeReferenceAttachments == false)
        #expect(reapplied.judgeConfiguration.hasCurrentExternalEvidenceApproval(for: connection))
    }

    @MainActor
    @Test func changingJudgeDestinationInvalidatesChecksAndSuiteDisclosure() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        var connection = EvaluationJudgeConnection(
            id: UUID(), name: "Local judge", kind: .localCompatible,
            baseURL: "http://127.0.0.1:11434/v1", modelID: "judge-v1",
            lastCheckedAt: Date(), lastCheckMessage: "Verified"
        )
        try store.saveJudgeConnection(connection, apiKey: nil)
        store.draftSuite.judgeConfiguration = .init(mode: .connection, connectionID: connection.id)
        store.approveExternalJudgeDisclosure()
        #expect(store.draftSuite.judgeConfiguration.hasCurrentExternalEvidenceApproval(for: connection))

        connection.modelID = "judge-v2"
        try store.saveJudgeConnection(connection, apiKey: nil)

        let saved = try #require(store.judgeConnections.first { $0.id == connection.id })
        #expect(saved.lastCheckedAt == nil)
        #expect(saved.lastCheckMessage == nil)
        #expect(!store.draftSuite.judgeConfiguration.hasCurrentExternalEvidenceApproval(for: saved))
    }

    @MainActor
    @Test func repositoryDefinitionConflictsDoNotOverwriteEitherSide() throws {
        let support = try temporaryDirectory()
        let repository = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: support)
            try? FileManager.default.removeItem(at: repository)
        }
        try runGit(["init"], in: repository)
        let store = EvaluationStore(supportDirectory: support)
        try store.linkSelectedProject(toRepository: repository.path)
        guard let definitionURL = EvaluationWorkspacePersistence.repositoryDefinitionURL(
            project: store.selectedProject, suite: store.selectedSuiteRecord
        ) else {
            Issue.record("Expected a linked repository definition.")
            return
        }
        var external = try CanonicalJSON.decode(
            EvaluationSuiteDefinition.self, from: Data(contentsOf: definitionURL)
        )
        external.instructions = "Externally edited instructions"
        let externalData = try CanonicalJSON.data(for: external)
        try externalData.write(to: definitionURL, options: .atomic)

        store.draftSuite.instructions = "Locally edited instructions"
        #expect(store.saveSuite() == false)
        #expect(store.notice?.contains("repository suite changed") == true)
        #expect(try Data(contentsOf: definitionURL) == externalData)
        #expect(store.suite.instructions != "Locally edited instructions")
        let reloaded = EvaluationStore(supportDirectory: support)
        #expect(reloaded.suite.instructions != "Locally edited instructions")
        #expect(reloaded.draftSuite.instructions == "Locally edited instructions")
    }

    @Test func featureAdapterExecutesSharedCodeAndUsesNormalScoring() async {
        var suite = EvaluationSuite()
        suite.scoringMode = .exactMatch
        suite.repetitions = 2
        suite.cases = [EvaluationCase(name: "Feature", prompt: "hello", expected: "HELLO")]
        let adapter = ClosureFeatureAdapter(displayName: "Uppercase") { input in input.prompt.uppercased() }
        let run = await EvaluationFeatureAdapterRunner().run(
            suiteRevision: "feature-v1", suite: suite, adapter: adapter
        )
        #expect(run.results.count == 2)
        #expect(run.results.allSatisfy { $0.status == .passed })
        #expect(run.environment.model == "Feature adapter · Uppercase")
        #expect(run.suiteDefinition?.id == suite.id)
    }

    @Test func structuredStarterUsesFieldAssertionsAsDeterministicScores() async {
        let suite = EvaluationStarterPack.structuredExtraction.makeSuite()
        let adapter = ClosureFeatureAdapter(displayName: "Expected fixture") { input in input.expected }

        let run = await EvaluationFeatureAdapterRunner().run(
            suiteRevision: "structured-v1", suite: suite, adapter: adapter
        )

        #expect(run.results.count == suite.cases.count)
        #expect(run.results.allSatisfy { $0.status == .passed })
        #expect(run.results.allSatisfy { $0.fieldAssertionResults?.isEmpty == false })
    }

    @MainActor
    @Test func targetedMCPListsAndActivatesStableWorkspaceIDs() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        let original = store.selectedSuiteID
        let second = try store.createSuite(name: "Automation target")
        try store.switchSuite(id: original)
        let authority = MCPStoreAuthority.make(store: store)
        let catalog = await authority.call(.listProjects).structuredContent
        guard case .array(let projects)? = catalog.objectValue?["projects"] else {
            Issue.record("Expected projects array.")
            return
        }
        #expect(!projects.isEmpty)
        let report = await authority.call(.releaseReport(.init(
            projectID: store.selectedProjectID, suiteID: second, runID: nil
        )))
        #expect(!report.isError)
        #expect(store.selectedSuiteID == second)
        #expect(report.structuredContent.objectValue?["report"]?.objectValue?["outcome"] == .integer(20))
    }

    @Test func repositorySnapshotRecordsCommitAndDirtyTree() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try runGit(["init"], in: directory)
        try runGit(["config", "user.email", "fixture@example.com"], in: directory)
        try runGit(["config", "user.name", "Fixture"], in: directory)
        try Data("one".utf8).write(to: directory.appending(path: "fixture.txt"))
        try runGit(["add", "fixture.txt"], in: directory)
        try runGit(["commit", "-m", "fixture"], in: directory)
        var snapshot = await EvaluationRepositoryInspector.snapshot(rootPath: directory.path)
        #expect(snapshot.commit?.isEmpty == false)
        #expect(snapshot.isDirty == false)
        try Data("two".utf8).write(to: directory.appending(path: "fixture.txt"))
        snapshot = await EvaluationRepositoryInspector.snapshot(rootPath: directory.path)
        #expect(snapshot.isDirty == true)
    }

    @Test func reassessmentReappliesFieldAssertionsWithoutGeneration() async {
        var suite = EvaluationSuite()
        suite.criteria = "The response is exactly READY."
        suite.cases[0].fieldAssertions = [
            .init(pointer: "/verified", operation: .equals, expectedValue: "true")
        ]
        var run = makeRun(cases: suite.cases, statuses: [[.passed]])
        run.suiteID = suite.id
        run.results[0].response = "READY"
        let connection = EvaluationJudgeConnection(
            id: UUID(), name: "Unused fixture", kind: .localCompatible,
            baseURL: "http://127.0.0.1:1/v1", modelID: "unused"
        )

        let assessment = await EvaluationReassessmentService().reassess(
            run: run, suite: suite, images: [],
            resolved: .init(connection: connection, apiKey: nil)
        )

        #expect(assessment.origin == .reassessment)
        #expect(assessment.samples.count == 1)
        #expect(assessment.samples[0].status == .failed)
        #expect(assessment.samples[0].trace?.judgedCriterionIndexes == [])
        #expect(assessment.errorCount == 0)
    }

    @MainActor
    @Test func correctionsAndBaselineApprovalsPreserveProvenanceDurably() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EvaluationStore(supportDirectory: directory)
        store.draftSuite.criteria = "The response is exactly READY."
        #expect(store.saveSuite())
        var run = makeRun(cases: store.suite.cases, statuses: [[.passed]])
        run.suiteID = store.suite.id
        run.suiteRevision = store.suiteRevision
        run.results[0].response = "READY"
        let connection = EvaluationJudgeConnection(
            id: UUID(), name: "Unused fixture", kind: .localCompatible,
            baseURL: "http://127.0.0.1:1/v1", modelID: "unused"
        )
        let assessment = await EvaluationReassessmentService().reassess(
            run: run, suite: store.suite, images: [],
            resolved: .init(connection: connection, apiKey: nil)
        )
        run.assessments = [assessment]
        run.selectedAssessmentID = assessment.id
        store.runs = [run]

        try store.markJudgmentIncorrect(
            runID: run.id, assessmentID: assessment.id, sampleID: run.results[0].id,
            correctedStatus: .failed, correctedScore: 1,
            reason: "The expected status was reviewed manually.", reviewer: "Test reviewer",
            collectAsJudgeCheck: true
        )
        try store.approveBaseline(runID: run.id, assessmentID: assessment.id, note: "Known fixture")

        #expect(store.runs[0].selectedAssessment?.samples[0].status == .passed)
        #expect(store.suiteLocalState.humanCorrections.last?.originalStatus == .passed)
        #expect(store.suiteLocalState.humanCorrections.last?.correctedStatus == .failed)
        #expect(store.suiteLocalState.reviewedJudgeExamples.last?.expectedStatus == .failed)
        #expect(store.activeBaselineApproval?.runID == run.id)
        #expect(store.activeBaselineApproval?.assessmentID == assessment.id)

        let reloaded = EvaluationStore(supportDirectory: directory)
        #expect(reloaded.suiteLocalState.humanCorrections.count == 1)
        #expect(reloaded.suiteLocalState.reviewedJudgeExamples.count == 1)
        #expect(reloaded.activeBaselineApproval?.assessmentID == assessment.id)
    }

    private func makeRun(cases: [EvaluationCase], statuses: [[EvaluationResultStatus]]) -> EvaluationRun {
        let now = Date()
        let results = zip(cases, statuses).flatMap { evaluationCase, caseStatuses in
            caseStatuses.enumerated().map { offset, status in
                EvaluationSampleResult(
                    caseID: evaluationCase.id, caseName: evaluationCase.name,
                    repetition: offset + 1, prompt: evaluationCase.prompt, expected: evaluationCase.expected,
                    response: "response", status: status, score: status == .passed ? 4 : 2,
                    rationale: nil, durationMilliseconds: Double(offset + 1), usage: .init(),
                    judgeDurationMilliseconds: nil, judgeUsage: nil,
                    errorCategory: nil, errorMessage: nil, judgeErrorCategory: nil, judgeErrorMessage: nil
                )
            }
        }
        return EvaluationRun(
            id: UUID(), suiteID: UUID(), suiteName: "Suite", suiteVersion: "v1",
            instructions: "", criteria: "Requirement", scoringMode: .modelJudge,
            repetitions: statuses.first?.count ?? 1, judgePromptVersion: "test", judgePassingScore: 3,
            plannedSampleCount: results.count, suiteRevision: "current", plannedCases: cases,
            startedAt: now, completedAt: now.addingTimeInterval(1), cancelled: false,
            terminationReason: nil,
            environment: .init(operatingSystem: "Test", locale: "en", model: "Fixture", modelContextSize: 1),
            attachments: [], results: results
        )
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIErrorForTests.git }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "EvaluationDevelopmentWorkflowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum CLIErrorForTests: Error { case git }
