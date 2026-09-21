import XCTest

@available(iOS 27.0, *)
@MainActor
final class IntentLabScenarioTests: XCTestCase {
    func testEnvironmentPayloadRequiresAnAtomicPair() {
        XCTAssertThrowsError(try IntentLabPayloadLoader.environmentData(
            named: "IntentLabScenario",
            environment: [IntentLabPayloadLoader.scenarioKey: Data("{}".utf8).base64EncodedString()]
        ))
    }

    func testEnvironmentPayloadOverridesBundledCompatibilityData() throws {
        var scenario = testScenario()
        scenario.safety.deadlineSeconds = 9
        let invocation = IntentLabInvocation(
            id: UUID(), nonce: "nonce", issuedAt: Date(),
            testIdentity: .init(
                bundleIdentifier: "dev.example.FixtureUITests",
                className: "IntentLabScenarioTests",
                methodName: "testIntentLabScenario"
            ),
            harnessVersion: "intent-lab-v1", destinationIdentifier: "device",
            scenarioDigest: scenario.definitionDigest, resultBundleIdentity: "result",
            appProduct: nil, testProduct: nil
        )
        let encoder = JSONEncoder.intentLab
        let environment = [
            IntentLabPayloadLoader.scenarioKey: try encoder.encode(scenario).base64EncodedString(),
            IntentLabPayloadLoader.invocationKey: try encoder.encode(invocation).base64EncodedString(),
        ]

        let data = try XCTUnwrap(IntentLabPayloadLoader.environmentData(
            named: "IntentLabScenario",
            environment: environment
        ))
        let decoded = try JSONDecoder.intentLab.decode(IntentLabScenario.self, from: data)
        XCTAssertEqual(decoded.safety.deadlineSeconds, 9)
    }

    func testHarnessRetainsWrongVisibleResultAsFailureEvidence() throws {
        var scenario = testScenario()
        scenario.assertions = [.init(
            id: UUID(),
            kind: .entityIdentifier,
            observationKey: "selectedNoteID",
            expectedValue: .string("packing-001"),
            required: true,
            applicableLanes: [.siri]
        )]

        let lane = result(
            for: .siri,
            scenario: scenario,
            observations: ["selectedNoteID": .string("garden-001")],
            startedAt: Date()
        )

        XCTAssertEqual(lane.outcome, .failed)
        XCTAssertEqual(lane.observations["selectedNoteID"], .string("garden-001"))
        XCTAssertEqual(lane.assertionResults.first?.observedValue, .string("garden-001"))
    }

    func testSemanticAssertionIsHandedToHostForReview() throws {
        var scenario = testScenario()
        scenario.assertions = [.init(
            id: UUID(),
            kind: .semanticRubric,
            observationKey: "visibleResponse",
            expectedValue: nil,
            required: true,
            applicableLanes: [.siri]
        )]

        let lane = result(
            for: .siri,
            scenario: scenario,
            observations: ["visibleResponse": .string("Opened the packing note")],
            startedAt: Date()
        )

        XCTAssertEqual(lane.outcome, .needsReview)
        XCTAssertEqual(lane.assertionResults.first?.observedValue, .string("Opened the packing note"))
    }

    func testSiriCompletionUsesCorrelationAndRetainsWrongResult() {
        let observations: [String: IntentLabValue] = [
            "invocationContext": .string("siri-attempt-1"),
            "selectedNoteID": .string("garden-001"),
        ]

        XCTAssertEqual(
            SiriProbe.correlatedCompletion(
                observations: observations,
                expectedContext: "siri-attempt-1"
            )?["selectedNoteID"],
            .string("garden-001")
        )
    }

    func testScenarioDeadlineIsDecodedForTheDeviceHarness() throws {
        let json = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "version":1,
          "definitionDigest":"digest",
          "target":{"bundleIdentifier":"dev.example.fixture"},
          "goal":{"requestText":"Open the note","languageCode":"en-GB"},
          "fixture":{"id":"notes","version":"1","digest":"fixture","preparationOperation":"reset","cleanupOperation":"reset"},
          "directControl":{"intentIdentifier":"OpenNoteIntent","parameters":[],"outputFields":[]},
          "assertions":[],
          "coverage":{"appFeature":"optional","intentIntegration":"required","siri":"required","siriAttemptCount":1},
          "safety":{"deadlineSeconds":7.25}
        }
        """
        let scenario = try JSONDecoder.intentLab.decode(IntentLabScenario.self, from: Data(json.utf8))
        XCTAssertEqual(SiriProbe.waitTimeout(for: scenario.safety), 7.25)
    }

    func testIntentLabScenario() async throws {
        let scenario: IntentLabScenario = try load("IntentLabScenario")
        let invocation: IntentLabInvocation = try load("IntentLabInvocation")
        guard scenario.schemaVersion == 1,
              invocation.harnessVersion == "intent-lab-v1",
              invocation.scenarioDigest == scenario.definitionDigest,
              let appProduct = invocation.appProduct,
              let testProduct = invocation.testProduct else {
            throw XCTSkip("The host did not embed a fully bound Intent Lab invocation.")
        }
        var results: [IntentLabLaneResult] = []

        if scenario.coverage.intentIntegration != .notApplicable {
            let context = "intent-\(invocation.id.uuidString)"
            let application = FixtureBridge.resetAndLaunch(
                bundleIdentifier: scenario.target.bundleIdentifier,
                context: context
            )
            let directStart = Date()
            do {
                var observations = try await IntentProbe.run(scenario)
                observations.merge(FixtureBridge.observations(from: application)) { direct, _ in direct }
                results.append(result(for: .intentIntegration, scenario: scenario, observations: observations, startedAt: directStart))
            } catch {
                results.append(failed(for: .intentIntegration, scenario: scenario, error: error, startedAt: directStart))
            }
        }

        if scenario.coverage.siri != .notApplicable {
            let attemptCount = scenario.coverage.siriAttemptCount ?? 3
            for attempt in 1...attemptCount {
                let context = "siri-\(invocation.id.uuidString)-\(attempt)"
                let application = FixtureBridge.resetAndLaunch(
                    bundleIdentifier: scenario.target.bundleIdentifier,
                    context: context
                )
                let siriStart = Date()
                do {
                    let observations = try SiriProbe.run(
                        request: scenario.goal.requestText,
                        application: application,
                        expectedContext: context,
                        safety: scenario.safety
                    )
                    let screenshot = EvidenceAttachmentWriter.attachScreenshot(to: self)
                    results.append(result(
                        for: .siri,
                        scenario: scenario,
                        observations: observations,
                        startedAt: siriStart,
                        attempt: attempt,
                        artifacts: [screenshot]
                    ))
                } catch {
                    let screenshot = EvidenceAttachmentWriter.attachScreenshot(to: self)
                    results.append(failed(
                        for: .siri,
                        scenario: scenario,
                        error: error,
                        startedAt: siriStart,
                        attempt: attempt,
                        artifacts: [screenshot]
                    ))
                }
            }
        }

        let process = ProcessInfo.processInfo
        let envelope = IntentLabEvidenceEnvelope(
            invocation: invocation,
            sourceBundleIdentifier: scenario.target.bundleIdentifier,
            observedAppProduct: appProduct,
            observedTestProduct: testProduct,
            environment: .init(
                xcodeVersion: process.environment["XCODE_VERSION_ACTUAL"] ?? "unknown",
                sdkVersion: process.environment["SDK_VERSION"] ?? "unknown",
                deviceModel: process.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "physical iPhone",
                operatingSystem: process.operatingSystemVersionString,
                operatingSystemBuild: nil,
                languageCode: Locale.current.language.languageCode?.identifier ?? scenario.goal.languageCode,
                regionCode: Locale.current.region?.identifier ?? "unknown",
                timeZoneIdentifier: TimeZone.current.identifier,
                siriConfiguration: "developer-declared by host setup",
                siriConfigurationSource: "manuallySupplied",
                executedAt: Date()
            ),
            testCount: 1,
            results: results
        )
        try EvidenceAttachmentWriter.attach(envelope, to: self)
        XCTAssertTrue(results.allSatisfy { $0.outcome == .passed || $0.outcome == .needsReview })
    }

    private func result(
        for lane: IntentLabLane,
        scenario: IntentLabScenario,
        observations: [String: IntentLabValue],
        startedAt: Date,
        attempt: Int = 1,
        artifacts: [IntentLabArtifactReference] = []
    ) -> IntentLabLaneResult {
        let assertions = scenario.assertions.filter {
            $0.applicableLanes?.contains(lane) ?? (lane != .appFeature)
        }
        let checks = assertions.map { assertion in
            let observed = observations[assertion.observationKey]
            if assertion.kind == .semanticRubric {
                return IntentLabAssertionResult(
                    assertionID: assertion.id,
                    passed: false,
                    observedValue: observed,
                    message: observed == nil
                        ? "Required semantic evidence was not captured."
                        : "Semantic evidence requires host assessment."
                )
            }
            return IntentLabAssertionResult(
                assertionID: assertion.id,
                passed: observed == assertion.expectedValue,
                observedValue: observed,
                message: observed == assertion.expectedValue ? "Matched the frozen expectation." : "Observed value did not match."
            )
        }
        let required = assertions.filter(\.required)
        let semanticIDs = Set(required.filter { $0.kind == .semanticRubric }.map(\.id))
        let missingSemantic = required.contains {
            $0.kind == .semanticRubric && observations[$0.observationKey] == nil
        }
        let deterministicFailure = checks.contains { check in
            !semanticIDs.contains(check.assertionID)
                && required.contains(where: { $0.id == check.assertionID })
                && !check.passed
        }
        let outcome: IntentLabOutcome
        if deterministicFailure || missingSemantic {
            outcome = .failed
        } else if !semanticIDs.isEmpty {
            outcome = .needsReview
        } else {
            outcome = .passed
        }
        return .init(
            caseID: scenario.id, attempt: attempt, lane: lane, executionStatus: .completed,
            outcome: outcome, startedAt: startedAt, completedAt: Date(),
            observations: observations, assertionResults: checks,
            diagnostic: nil, proposedCause: nil, artifacts: artifacts,
            observationSources: Dictionary(uniqueKeysWithValues: observations.keys.map {
                ($0, lane == .siri ? "applicationInstrumentation" : "appIntentsTesting")
            })
        )
    }

    private func failed(
        for lane: IntentLabLane,
        scenario: IntentLabScenario,
        error: Error,
        startedAt: Date,
        attempt: Int = 1,
        artifacts: [IntentLabArtifactReference] = []
    ) -> IntentLabLaneResult {
        let executionStatus: IntentLabExecutionStatus
        switch error {
        case SiriProbeError.outcomeNotObserved:
            executionStatus = .timedOut
        case is SiriProbeError:
            executionStatus = .blockedByEnvironment
        default:
            executionStatus = .completed
        }
        return .init(
            caseID: scenario.id, attempt: attempt, lane: lane,
            executionStatus: executionStatus,
            outcome: .notObserved, startedAt: startedAt, completedAt: Date(), observations: [:],
            assertionResults: [], diagnostic: error.localizedDescription,
            proposedCause: nil, artifacts: artifacts, observationSources: nil
        )
    }

    private func load<Value: Decodable>(_ name: String) throws -> Value {
        if let data = try IntentLabPayloadLoader.environmentData(named: name) {
            return try JSONDecoder.intentLab.decode(Value.self, from: data)
        }
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        return try JSONDecoder.intentLab.decode(Value.self, from: Data(contentsOf: url))
    }

    private func testScenario() -> IntentLabScenario {
        IntentLabScenario(
            id: UUID(),
            version: 1,
            definitionDigest: "test-digest",
            target: .init(bundleIdentifier: "dev.example.fixture"),
            goal: .init(requestText: "Open the packing note", languageCode: "en-GB"),
            fixture: .init(
                id: "notes",
                version: "1",
                digest: "fixture-digest",
                preparationOperation: "reset",
                cleanupOperation: "reset"
            ),
            directControl: .init(intentIdentifier: "OpenNoteIntent", parameters: [], outputFields: []),
            assertions: [],
            coverage: .init(
                appFeature: .optional,
                intentIntegration: .required,
                siri: .required,
                siriAttemptCount: 1
            ),
            safety: .init(deadlineSeconds: 60)
        )
    }
}

private extension IntentLabValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
