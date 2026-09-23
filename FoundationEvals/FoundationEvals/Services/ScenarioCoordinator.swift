import Foundation
import Observation

@MainActor
@Observable
final class ScenarioCoordinator {
    private(set) var definitions: [ScenarioDefinition] = []
    private(set) var runs: [ScenarioRun] = []
    var draft: ScenarioDefinition
    var selectedRunID: UUID?
    var configuration: XcodeTestConfiguration
    var projectTrusted = false
    private(set) var connectionDiscovery: XcodeConnectionDiscovery?
    private(set) var discoveredDevices: [IntentLabDeviceDestination] = []
    private(set) var isDiscoveringConnection = false
    var statedChangedDimensions: Set<String> = []
    private(set) var preflight: ScenarioPreflightReport?
    private(set) var isRunning = false
    private(set) var isGeneratingSuggestions = false
    private(set) var suggestions: [ScenarioRequestSuggestion] = []
    private(set) var recoveryJournals: [ScenarioExecutionJournal] = []
    private(set) var hasLoaded = false
    var notice: String?

    private let persistence: ScenarioPersistence
    private let executor: XcodeTestExecutor
    private let rootDirectory: URL
    private let evaluationStore: EvaluationStore
    private var ledger = ScenarioImportLedger()

    init(supportDirectory: URL, evaluationStore: EvaluationStore) {
        let root = supportDirectory.appending(path: "IntentLab", directoryHint: .isDirectory)
        rootDirectory = root
        let persistence = ScenarioPersistence(rootDirectory: root)
        self.persistence = persistence
        self.evaluationStore = evaluationStore
        executor = XcodeTestExecutor(
            workDirectory: root.appending(path: "Executor", directoryHint: .isDirectory),
            persistence: persistence
        )
        draft = (try? ScenarioDefinition.starter().frozen()) ?? ScenarioDefinition.starter()
        configuration = .init(
            containerPath: "",
            isWorkspace: false,
            scheme: "IntentLabFixture",
            testTarget: "IntentLabFixtureUITests",
            testBundleIdentifier: "com.example.IntentLabFixtureUITests",
            destinationIdentifier: "",
            generatedResourceDirectory: ""
        )
    }

    var selectedRun: ScenarioRun? {
        selectedRunID.flatMap { id in runs.first { $0.id == id } }
    }

    var currentValidationIssues: [ScenarioValidationIssue] {
        ScenarioValidator.issues(in: draft, requireFrozenDigest: false)
    }

    func definition(for run: ScenarioRun) -> ScenarioDefinition? {
        definitions.first {
            $0.id == run.scenarioID &&
            $0.version == run.scenarioVersion &&
            $0.definitionDigest == run.scenarioDigest
        } ?? (draft.id == run.scenarioID && draft.version == run.scenarioVersion && draft.definitionDigest == run.scenarioDigest ? draft : nil)
    }

    func load() async {
        guard !hasLoaded else { return }
        do {
            try await persistence.prepare()
            definitions = try await persistence.loadDefinitions()
            runs = try await persistence.loadRuns()
            ledger = try await persistence.loadLedger()
            recoveryJournals = try await executor.reconcileInterruptedJournals()
            if let definition = definitions.last {
                draft = definition
                applyTargetToConfiguration(definition.target)
            }
            // The saved connection profile is the most recent operator choice. A frozen
            // scenario can carry older target metadata, so it must not overwrite that profile.
            if let savedConfiguration = try await persistence.loadExecutionConfiguration() {
                configuration = savedConfiguration
            }
            selectedRunID = runs.first?.id
            if !recoveryJournals.isEmpty {
                notice = "A previous device test ended without proven cleanup. Its destination is quarantined until termination and fixture readiness are confirmed."
            }
            hasLoaded = true
            await refreshDevices()
        } catch {
            notice = "Intent Lab storage could not be loaded: \(error.localizedDescription)"
        }
    }

    func selectContainer(_ url: URL) {
        guard ["xcodeproj", "xcworkspace"].contains(url.pathExtension.lowercased()) else {
            notice = XcodeConnectionDiscoveryError.invalidContainer.localizedDescription
            return
        }
        configuration.containerPath = url.standardizedFileURL.path
        configuration.isWorkspace = url.pathExtension == "xcworkspace"
        configuration.scheme = ""
        configuration.testTarget = ""
        configuration.testBundleIdentifier = ""
        configuration.harnessVersion = nil
        configuration.harnessCapabilities = nil
        configuration.applicationSigningConfigured = nil
        configuration.testSigningConfigured = nil
        projectTrusted = false
        connectionDiscovery = nil
        preflight = nil
    }

    func refreshDevices() async {
        do {
            let service = XcodeConnectionDiscoveryService(
                xcodebuildPath: configuration.xcodebuildPath,
                xcdevicePath: "/usr/bin/xcrun"
            )
            discoveredDevices = try await Task.detached {
                try service.discoverDevices()
            }.value
        } catch {
            discoveredDevices = []
            if recoveryJournals.isEmpty {
                notice = error.localizedDescription
            }
        }
    }

    func approveBuildAndDiscover() async {
        guard !configuration.containerPath.isEmpty else {
            notice = XcodeConnectionDiscoveryError.invalidContainer.localizedDescription
            return
        }
        isDiscoveringConnection = true
        defer { isDiscoveringConnection = false }
        let approvedContainerPath = configuration.containerPath
        do {
            let container = URL(filePath: approvedContainerPath)
            let service = XcodeConnectionDiscoveryService(
                xcodebuildPath: configuration.xcodebuildPath,
                xcdevicePath: "/usr/bin/xcrun"
            )
            let buildConfiguration = configuration.configuration
            let discovery = try await Task.detached {
                try service.discoverProject(container: container, configuration: buildConfiguration)
            }.value
            guard configuration.containerPath == approvedContainerPath else { return }
            connectionDiscovery = discovery
            projectTrusted = true
            apply(discovery: discovery)
            try await persistence.saveExecutionConfiguration(configuration)
            await refreshPreflight()
        } catch {
            guard configuration.containerPath == approvedContainerPath else { return }
            projectTrusted = false
            connectionDiscovery = nil
            notice = error.localizedDescription
        }
    }

    func selectScheme(_ scheme: String) {
        configuration.scheme = scheme
        preflight = nil
    }

    func selectApplication(_ product: XcodeDiscoveredProduct) {
        draft.target.bundleIdentifier = product.bundleIdentifier
        configuration.applicationSigningConfigured = product.signingConfigured
        draft.definitionDigest = ""
        preflight = nil
    }

    func selectUITestBundle(_ product: XcodeDiscoveredProduct) {
        configuration.testTarget = product.targetName
        configuration.testBundleIdentifier = product.bundleIdentifier
        configuration.harnessVersion = product.harnessVersion
        configuration.harnessCapabilities = product.harnessCapabilities
        configuration.testSigningConfigured = product.signingConfigured
        preflight = nil
    }

    func selectDevice(_ identifier: String) async {
        configuration.destinationIdentifier = identifier
        preflight = nil
        try? await persistence.saveExecutionConfiguration(configuration)
        if projectTrusted { await refreshPreflight() }
    }

    func artifactURL(run: ScenarioRun, artifact: ScenarioArtifactReference) -> URL {
        rootDirectory
            .appending(path: "Runs/\(run.scenarioID.uuidString)/\(run.id.uuidString)", directoryHint: .isDirectory)
            .appending(path: artifact.relativePath)
    }

    func comparison(for run: ScenarioRun) -> ScenarioComparisonReport? {
        guard let baseline = runs.first(where: {
            $0.id != run.id && $0.scenarioID == run.scenarioID && $0.startedAt < run.startedAt
        }) else { return nil }
        return ScenarioComparison.compare(baseline: baseline, candidate: run)
    }

    @discardableResult
    func freezeAndSave() async throws -> ScenarioDefinition {
        applyConfigurationToDraft()
        draft.version = max(1, draft.version)
        draft = try draft.frozen()
        try ScenarioValidator.validate(draft)
        let frozen = draft
        let savedConfiguration = configuration
        try await persistence.saveDefinition(frozen)
        try await persistence.saveExecutionConfiguration(savedConfiguration)
        if let index = definitions.firstIndex(where: { $0.id == frozen.id && $0.version == frozen.version }) {
            definitions[index] = frozen
        } else {
            definitions.append(frozen)
        }
        return frozen
    }

    func duplicateAsNewVersion() {
        draft.version += 1
        draft.definitionDigest = ""
        selectedRunID = nil
        preflight = nil
    }

    func refreshPreflight() async {
        applyConfigurationToDraft()
        guard let frozen = try? draft.frozen() else { return }
        draft = frozen
        try? await persistence.saveExecutionConfiguration(configuration)
        preflight = await executor.preflight(
            definition: frozen,
            configuration: configuration,
            projectTrusted: projectTrusted,
            linkedFeatureEvidenceAvailable: linkedFeatureRun(for: frozen) != nil
        )
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        var pendingJournal: ScenarioExecutionJournal?
        let runConfiguration = configuration
        let runTrusted = projectTrusted
        let changedDimensions = statedChangedDimensions
        let linkedRun = linkedFeatureRun(for: draft)
        do {
            let definition = try await freezeAndSave()
            let result = try await executor.execute(
                definition: definition,
                configuration: runConfiguration,
                projectTrusted: runTrusted,
                linkedFeatureEvidenceAvailable: linkedRun != nil
            )
            pendingJournal = result.journal
            guard result.reportedTestCount == 1 else {
                throw ScenarioEvidenceImportError.invalidTestCount
            }
            var imported: [ScenarioRun] = []
            let featureResult = linkedRun.map {
                ScenarioFeatureEvidence.laneResult(from: $0, definition: definition)
            }
            for attachment in result.evidenceAttachments {
                var run = try XCTestEvidenceImporter().importEvidence(
                    data: Data(contentsOf: attachment.url),
                    definition: definition,
                    journal: result.journal,
                    artifactRoot: result.attachmentDirectory,
                    ledger: &ledger,
                    supplementaryResults: featureResult.map { [$0] } ?? [],
                    statedChangedDimensions: changedDimensions
                )
                if result.processExitCode != 0,
                   attachment.isCheckpoint,
                   let failure = result.testFailureMessages.first,
                   let index = run.laneResults.firstIndex(where: { $0.lane == .siri }) {
                    run.laneResults[index].diagnostic = ScenarioDiagnosticClassifier.checkpointDiagnostic(for: failure)
                }
                if run.outcome == .needsReview {
                    do {
                        run = try await ScenarioResponseAssessmentService.assess(run, definition: definition)
                    } catch {
                        notice = "The run was retained, but semantic assessment needs review: \(error.localizedDescription)"
                    }
                }
                imported.append(try await persistence.saveRun(run, artifactRoot: result.attachmentDirectory))
            }
            try await persistence.saveLedger(ledger)
            let hasFinalEvidence = result.evidenceAttachments.allSatisfy { !$0.isCheckpoint }
            try await executor.finishEvidenceValidation(journal: result.journal, accepted: hasFinalEvidence)
            pendingJournal = nil
            recoveryJournals = try await executor.currentRecoveryJournals()
            runs.insert(contentsOf: imported, at: 0)
            selectedRunID = imported.first?.id
            if statedChangedDimensions == changedDimensions { statedChangedDimensions.removeAll() }
            notice = imported.first.map {
                result.processExitCode == 0
                    ? "Scenario imported as \($0.outcome.rawValue). Direct intent and Siri evidence remain separately labelled."
                    : "The UI test failed (exit \(result.processExitCode)); its available evidence was retained as \($0.outcome.rawValue)."
            }
        } catch {
            if let pendingJournal {
                try? await executor.finishEvidenceValidation(journal: pendingJournal, accepted: false)
            }
            recoveryJournals = (try? await executor.currentRecoveryJournals()) ?? recoveryJournals
            notice = error.localizedDescription
        }
        await refreshPreflight()
    }

    func cancel() async {
        if let journal = await executor.cancelActiveExecution() {
            recoveryJournals.removeAll { $0.id == journal.id }
            recoveryJournals.append(journal)
        }
        notice = "Cancellation requested. The device is quarantined until test termination and fixture readiness are proven."
        await refreshPreflight()
    }

    func clearDeviceQuarantine(fixtureReadinessProven: Bool) async {
        do {
            try await executor.clearQuarantine(
                destinationIdentifier: configuration.destinationIdentifier,
                fixtureReadinessProven: fixtureReadinessProven
            )
            recoveryJournals.removeAll { $0.invocation.destinationIdentifier == configuration.destinationIdentifier }
            await refreshPreflight()
        } catch {
            notice = error.localizedDescription
        }
    }

    func generateSuggestions() async {
        guard !isGeneratingSuggestions else { return }
        isGeneratingSuggestions = true
        defer { isGeneratingSuggestions = false }
        do {
            let frozen = try draft.frozen()
            suggestions = try await ScenarioSuggestionService.generate(for: frozen)
        } catch {
            notice = error.localizedDescription
        }
    }

    func approveSuggestion(id: UUID) {
        guard let index = suggestions.firstIndex(where: { $0.id == id }) else { return }
        suggestions[index].approved = true
        approveSuggestion(suggestions[index])
    }

    func approveSuggestion(_ suggestion: ScenarioRequestSuggestion) {
        if definitions.contains(where: { $0.id == draft.id && $0.version == draft.version }) {
            duplicateAsNewVersion()
        } else {
            draft.definitionDigest = ""
        }
        draft.goal.requestText = suggestion.requestText
    }

    func releaseReport(for run: ScenarioRun?) -> ScenarioReleaseCheckReport {
        let definition = run.flatMap { definition(for: $0) } ?? draft
        return ScenarioReleaseCheckEvaluator.report(
            definition: definition,
            run: run,
            comparison: run.flatMap(comparison(for:))
        )
    }

    private func applyConfigurationToDraft() {
        draft.target.projectPath = configuration.containerPath
        draft.target.scheme = configuration.scheme
        draft.target.testTarget = configuration.testTarget
        draft.target.destinationIdentifier = configuration.destinationIdentifier
        draft.definitionDigest = ""
    }

    private func applyTargetToConfiguration(_ target: ScenarioTarget) {
        configuration.containerPath = target.projectPath
        configuration.isWorkspace = target.projectPath.hasSuffix(".xcworkspace")
        configuration.scheme = target.scheme
        configuration.testTarget = target.testTarget
        configuration.destinationIdentifier = target.destinationIdentifier
    }

    private func apply(discovery: XcodeConnectionDiscovery) {
        if let scheme = discovery.automaticallySelectedScheme {
            configuration.scheme = scheme
        } else if !discovery.schemes.contains(configuration.scheme) {
            configuration.scheme = ""
        }
        if discovery.applications.count == 1, let application = discovery.applications.first {
            selectApplication(application)
        } else if !discovery.applications.contains(where: { $0.bundleIdentifier == draft.target.bundleIdentifier }) {
            draft.target.bundleIdentifier = ""
            draft.definitionDigest = ""
            configuration.applicationSigningConfigured = nil
        }
        if discovery.uiTestBundles.count == 1, let tests = discovery.uiTestBundles.first {
            selectUITestBundle(tests)
        } else if !discovery.uiTestBundles.contains(where: { $0.targetName == configuration.testTarget }) {
            configuration.testTarget = ""
            configuration.testBundleIdentifier = ""
            configuration.harnessVersion = nil
            configuration.harnessCapabilities = nil
            configuration.testSigningConfigured = nil
        }
    }

    private func linkedFeatureRun(for definition: ScenarioDefinition) -> EvaluationRun? {
        definition.directControl.linkedFeatureRunID.flatMap(evaluationStore.run(with:))
    }
}
