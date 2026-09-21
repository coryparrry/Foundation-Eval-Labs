import Foundation
import Testing
@testable import FoundationEvals

struct IntentLabRegressionTests {
    @Test func injectedSemanticAssessmentFinalizesLaneAndRunOutcome() async throws {
        var definition = ScenarioDefinition.starter()
        let assertion = ScenarioAssertion(
            kind: .semanticRubric,
            observationKey: "visibleResponse",
            explanation: "The response confirms that the packing note opened.",
            applicableLanes: [.siri]
        )
        definition.assertions = [assertion]
        definition.coverage.intentIntegration = .notApplicable
        definition = try definition.frozen()
        let now = Date()
        let invocation = ScenarioInvocationIdentity(
            id: UUID(),
            nonce: UUID().uuidString,
            issuedAt: now,
            testIdentity: .init(
                bundleIdentifier: "dev.example.FixtureUITests",
                className: "IntentLabScenarioTests",
                methodName: "testIntentLabScenario"
            ),
            harnessVersion: ScenarioInvocationIdentity.currentHarnessVersion,
            destinationIdentifier: "physical-device-1",
            scenarioDigest: definition.definitionDigest,
            resultBundleIdentity: UUID().uuidString
        )
        let run = ScenarioRun(
            id: invocation.id,
            scenarioID: definition.id,
            scenarioVersion: definition.version,
            scenarioDigest: definition.definitionDigest,
            invocation: invocation,
            startedAt: now,
            completedAt: now,
            environment: .init(
                xcodeVersion: "27", sdkVersion: "27", deviceModel: "iPhone",
                operatingSystem: "iOS 27", languageCode: "en", regionCode: "GB",
                timeZoneIdentifier: "Europe/London", executedAt: now
            ),
            executionStatus: .completed,
            outcome: .needsReview,
            laneResults: [.init(
                caseID: definition.id,
                attempt: 1,
                lane: .siri,
                executionStatus: .completed,
                outcome: .needsReview,
                startedAt: now,
                completedAt: now,
                observations: ["visibleResponse": .string("Opened the packing note")],
                assertionResults: [.init(
                    assertionID: assertion.id,
                    passed: false,
                    observedValue: .string("Opened the packing note"),
                    message: "Pending semantic review."
                )]
            )],
            linkedFeatureRunID: nil,
            importedAt: now
        )

        let assessed = try await ScenarioResponseAssessmentService.assess(
            run,
            definition: definition
        ) { receivedAssertion, response, _ in
            #expect(receivedAssertion.id == assertion.id)
            #expect(response == "Opened the packing note")
            return ScenarioSemanticAssessment(passed: true, explanation: "The response satisfies the rubric.")
        }

        #expect(assessed.laneResults[0].outcome == .passed)
        #expect(assessed.laneResults[0].assertionResults[0].passed)
        #expect(assessed.outcome == .passed)
        #expect(assessed.responseAssessments?.first?.passed == true)
    }

    @MainActor
    @Test func approvingWordingCreatesANewFrozenVersion() async throws {
        let root = try temporaryDirectory()
        let store = EvaluationStore(supportDirectory: root)
        let coordinator = ScenarioCoordinator(supportDirectory: root, evaluationStore: store)
        await coordinator.load()
        coordinator.configuration.containerPath = "/tmp/Fixture.xcodeproj"
        coordinator.configuration.destinationIdentifier = "physical-device-1"
        coordinator.configuration.generatedResourceDirectory = "/tmp/Generated"
        try await coordinator.freezeAndSave()
        let originalVersion = coordinator.draft.version

        coordinator.approveSuggestion(.init(
            requestText: "Open my packing note in the fixture app",
            category: "paraphrase",
            note: "Approved alternate wording"
        ))

        #expect(coordinator.draft.version == originalVersion + 1)
        #expect(coordinator.draft.definitionDigest.isEmpty)
        #expect(coordinator.draft.goal.requestText == "Open my packing note in the fixture app")

        try await coordinator.freezeAndSave()
        let reloaded = ScenarioPersistence(
            rootDirectory: store.overviewStorageDirectory.appending(path: "IntentLab", directoryHint: .isDirectory)
        )
        let saved = try await reloaded.loadDefinitions().filter { $0.id == coordinator.draft.id }
        #expect(saved.map(\.version).sorted() == [originalVersion, originalVersion + 1])
        #expect(saved.last(where: { $0.version == originalVersion + 1 })?.goal.requestText == "Open my packing note in the fixture app")
    }

    @MainActor
    @Test func executionSetupReloadsButProjectTrustDoesNot() async throws {
        let root = try temporaryDirectory()
        let store = EvaluationStore(supportDirectory: root)
        let persistence = ScenarioPersistence(
            rootDirectory: store.overviewStorageDirectory.appending(path: "IntentLab", directoryHint: .isDirectory)
        )
        var olderDefinition = ScenarioDefinition.starter()
        olderDefinition.target.projectPath = "/tmp/Old.xcodeproj"
        olderDefinition.target.scheme = "OldScheme"
        olderDefinition.target.destinationIdentifier = "old-device"
        olderDefinition = try olderDefinition.frozen()
        try await persistence.saveDefinition(olderDefinition)
        let coordinator = ScenarioCoordinator(supportDirectory: root, evaluationStore: store)
        await coordinator.load()
        coordinator.configuration.containerPath = "/tmp/Fixture.xcodeproj"
        coordinator.configuration.scheme = "Fixture"
        coordinator.configuration.destinationIdentifier = "physical-device-1"
        coordinator.configuration.testBundleIdentifier = "dev.example.FixtureUITests"
        coordinator.configuration.generatedResourceDirectory = "/tmp/FixtureGenerated"
        coordinator.projectTrusted = true
        await coordinator.refreshPreflight()

        let reloaded = ScenarioCoordinator(supportDirectory: root, evaluationStore: store)
        await reloaded.load()

        #expect(reloaded.configuration.testBundleIdentifier == "dev.example.FixtureUITests")
        #expect(reloaded.configuration.generatedResourceDirectory == "/tmp/FixtureGenerated")
        #expect(reloaded.configuration.containerPath == "/tmp/Fixture.xcodeproj")
        #expect(reloaded.configuration.scheme == "Fixture")
        #expect(reloaded.configuration.destinationIdentifier == "physical-device-1")
        #expect(reloaded.projectTrusted == false)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "IntentLabRegressionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
