import Foundation
@testable import FoundationEvalsIntegration
import Testing

private struct ReceiptInput: Codable, Sendable {
    var text: String
}

private struct ReceiptOutput: Codable, Sendable {
    var shop: String?
    var totalPence: Int?
}

private struct SecretInputFeature: FeatureUnderTest {
    var received: @Sendable (ReceiptInput) -> Void = { _ in }

    func evaluate(_ input: ReceiptInput) async throws -> ReceiptOutput {
        received(input)
        return ReceiptOutput(shop: "Example Shop", totalPence: 1000)
    }
}

private struct ScriptedFeature: FeatureUnderTest {
    enum Outcome: Sendable {
        case output(ReceiptOutput)
        case failure
    }

    var outputs: [String: Outcome]

    func evaluate(_ input: ReceiptInput) async throws -> ReceiptOutput {
        switch outputs[input.text] {
        case .output(let output): return output
        case .failure: throw CaptureBundleError.captureFailed("scripted failure")
        case nil: throw CaptureBundleError.captureFailed("unexpected input")
        }
    }
}

private struct NullFeature: FeatureUnderTest {
    struct Input: Codable, Sendable { var text: String }
    struct Output: Codable, Sendable { var value: CaptureJSON }

    func evaluate(_ input: Input) async throws -> Output {
        Output(value: .null)
    }
}

struct CaptureContractTests {
    @Test func expectedSecretDoesNotEnterFeatureInput() async throws {
        let secret = "SECRET-EXPECTED-MARKER-7f3a"
        nonisolated(unsafe) var seen: [ReceiptInput] = []
        let feature = SecretInputFeature { seen.append($0) }
        let input = ReceiptInput(text: "Example Shop\nTotal paid: GBP 7.50")
        _ = try await feature.evaluate(input)
        let encoded = try CaptureJSON.fromEncoded(input)
        let data = try CaptureJSONCoding.encoder().encode(encoded)
        #expect(!String(decoding: data, as: UTF8.self).contains(secret))
        #expect(seen.count == 1)
        #expect(!seen[0].text.contains(secret))
    }

    @Test func caseIdentityStaysStableAcrossRuns() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = try samplePlan()
        let first = try await run(plan: plan, in: directory, runID: UUID())
        let second = try await run(plan: plan, in: directory, runID: UUID())
        let firstBundle = try CaptureBundleValidator.load(root: first)
        let secondBundle = try CaptureBundleValidator.load(root: second)
        #expect(firstBundle.manifest.run.runID != secondBundle.manifest.run.runID)
        #expect(firstBundle.observations[0].coordinate.caseID == "ordinary")
        #expect(secondBundle.observations[0].coordinate.caseID == "ordinary")
    }

    @Test func returnedWrongTotalKeepsExecutionAndSeparateCheck() throws {
        let observation = CaptureObservation(
            coordinate: .init(caseID: "discounted", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("Subtotal: GBP 10.00\nTotal paid: GBP 7.50")]),
            output: .returned(.object(["totalPence": .number("1000")])),
            execution: .returned,
            durationMilliseconds: 12,
            checks: [
                CaptureCheck(
                    id: "total-pence",
                    name: "expectedTotalPence",
                    status: .failed,
                    semantics: "producer-reported",
                    value: .number("750"),
                    rationale: "Returned 1000, expected 750"
                )
            ]
        )
        #expect(observation.execution == .returned)
        #expect(observation.checks[0].status == .failed)
        if case .returned(let json) = observation.output, case .object(let object) = json {
            #expect(object["totalPence"] == .number("1000"))
        } else {
            Issue.record("Expected the returned 1000 pence output.")
        }
    }

    @Test func laterThrowKeepsEarlierObservations() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let feature = ScriptedFeature(outputs: [
            "one": .output(.init(shop: "A", totalPence: 100)),
            "two": .output(.init(shop: "B", totalPence: 200)),
            "three": .failure
        ])
        let plan = CapturePlan(cases: [
            try planCase(id: "one", text: "one"),
            try planCase(id: "two", text: "two"),
            try planCase(id: "three", text: "three")
        ])
        let writer = try CaptureBundleWriter(
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        let url = try await CaptureSession(feature: feature, writer: writer).run(plan: plan)
        let bundle = try CaptureBundleValidator.load(root: url)
        let byID = Dictionary(uniqueKeysWithValues: bundle.observations.map { ($0.coordinate.caseID, $0) })
        #expect(bundle.observations.count == 3)
        #expect(byID["one"]?.execution == .returned)
        #expect(byID["two"]?.execution == .returned)
        #expect(byID["three"]?.execution == .threw)
        #expect(byID["three"]?.output == .absent)
        #expect(bundle.manifest.run.state == .finished)
    }

    @Test func evaluatorFailureKeepsReturnedOutput() {
        let observation = CaptureObservation(
            coordinate: .init(caseID: "discounted", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("Total paid: GBP 7.50")]),
            output: .returned(.object(["totalPence": .number("1000")])),
            execution: .returned,
            durationMilliseconds: 4,
            evaluatorError: .init(kind: "evaluator", message: "check crashed"),
            checks: []
        )
        #expect(observation.execution == .returned)
        if case .returned(let value) = observation.output {
            #expect(value != .null)
        } else {
            Issue.record("Feature output was dropped after the evaluator failed.")
        }
        #expect(observation.evaluatorError?.kind == "evaluator")
    }

    @Test func transcriptHookFailureKeepsFeatureOutput() {
        let observation = CaptureObservation(
            coordinate: .init(caseID: "ordinary", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("Example Shop")]),
            output: .returned(.object(["totalPence": .number("1000")])),
            execution: .returned,
            durationMilliseconds: 4,
            transcriptError: .init(kind: "transcript", message: "session snapshot failed")
        )
        #expect(observation.execution == .returned)
        #expect(observation.transcriptError != nil)
        #expect(observation.output != .absent)
    }

    @Test func cancelBeforeNextCaseLeavesItUnattempted() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = CapturePlan(cases: [
            try planCase(id: "one", text: "one"),
            try planCase(id: "two", text: "two")
        ])
        let writer = try CaptureBundleWriter(
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        try await writer.begin()
        try await writer.record(CaptureObservation(
            coordinate: .init(caseID: "one", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("one")]),
            output: .returned(.object(["totalPence": .number("1")])),
            execution: .returned,
            durationMilliseconds: 1
        ))
        let url = try await writer.finish(state: .cancelled)
        let bundle = try CaptureBundleValidator.load(root: url)
        #expect(bundle.coverage.missingCoordinates.map(\.caseID) == ["two"])
        #expect(bundle.observations.count == 1)
        #expect(bundle.manifest.run.state == .cancelled)
    }

    @Test func interruptedWriterKeepsCompleteObservations() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = CapturePlan(cases: [
            try planCase(id: "one", text: "one"),
            try planCase(id: "two", text: "two"),
            try planCase(id: "three", text: "three")
        ])
        let writer = try CaptureBundleWriter(
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        try await writer.begin()
        try await writer.record(CaptureObservation(
            coordinate: .init(caseID: "one", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("one")]),
            output: .returned(.null),
            execution: .returned,
            durationMilliseconds: 1
        ))
        try await writer.record(CaptureObservation(
            coordinate: .init(caseID: "two", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("two")]),
            output: .returned(.object(["totalPence": .number("2")])),
            execution: .returned,
            durationMilliseconds: 1
        ))
        let recovery = try CaptureBundleWriter.inspectWorkingDirectory(await writer.workingURL)
        #expect(recovery.completeObservations.count == 2)
        #expect(recovery.canClaimFinished == false)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "\(await writer.runID.uuidString).fevalrun").path))
    }

    @Test func publishedBundleDropsJournalFilesAndHonorsByteBudget() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let limits = CaptureLimits(
            maximumObservationLineBytes: 8_192,
            maximumBundleBytes: 4_096,
            maximumRegularFiles: 8
        )
        let plan = CapturePlan(cases: [
            CapturePlanCase(caseID: "one", inputRevision: "v1", input: .object(["text": .string("one")]))
        ])
        let writer = try CaptureBundleWriter(
            outputParent: directory,
            limits: limits,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        try await writer.begin()
        try await writer.record(CaptureObservation(
            coordinate: .init(caseID: "one", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("one")]),
            output: .returned(.null),
            execution: .returned,
            durationMilliseconds: 1
        ))
        let published = try await writer.finish(state: .finished)
        #expect(!FileManager.default.fileExists(atPath: published.appending(path: "observations").path))
        #expect(!FileManager.default.fileExists(atPath: published.appending(path: "plan.json").path))
        #expect(FileManager.default.fileExists(atPath: published.appending(path: "observations.jsonl").path))

        let huge = CaptureJSON.string(String(repeating: "x", count: 3_500))
        let second = try CaptureBundleWriter(
            outputParent: directory,
            limits: limits,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        try await second.begin()
        await #expect(throws: CaptureFileIOError.self) {
            try await second.record(CaptureObservation(
                coordinate: .init(caseID: "one", repetition: 1),
                inputRevision: "v1",
                input: huge,
                output: .returned(huge),
                execution: .returned,
                durationMilliseconds: 1
            ))
        }
    }

    @Test func appleEvaluationJSONKeepsSampleRows() throws {
        let data = Data(
            """
            {"resultID":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","evaluationID":"ReceiptNativeEvaluation","evaluationInfo":{},"startTime":"2026-09-17T19:17:18Z","endTime":"2026-09-17T19:17:18Z","runErrors":{"inferenceFailureCount":1,"evaluatorFailureCount":1,"failingEvaluatorTypes":[],"metricsNotFound":[]},"results":[{"Input":"{\\"input\\":{\\"prompt\\":\\"hi\\"}}","Response":{"value":"{\\"totalPence\\":1000}"},"Expected":"{}","SubjectInferenceError":null,"EvaluatorErrors":null,"paidTotal":{"kind":"fail","value":false},"penceScale":{"kind":"score","value":99}},{"Input":"{}","Response":null,"Expected":"{}","SubjectInferenceError":"threw","EvaluatorErrors":null},{"Input":"{}","Response":{"value":"{}"},"Expected":"{}","EvaluatorErrors":["eval failed"],"penceScale":{"kind":"ignore"}}]}
            """.utf8
        )
        let inspection = try AppleEvaluationJSONInspector.inspect(bytes: data)
        #expect(inspection.samples.count == 3)
        #expect(inspection.samples[0].fields["response"]?.contains("1000") == true)
        #expect(inspection.samples[0].metrics.contains { $0.name == "paidTotal" && $0.kind == "fail" })
        #expect(inspection.samples[1].subjectError == "threw")
        #expect(inspection.samples[2].evaluatorError == "eval failed")
        #expect(inspection.warnings.contains(AppleEvaluationInspectionLabels.ignoredCheck))
        #expect(!inspection.warnings.contains(AppleEvaluationInspectionLabels.metadataOnly))
    }

    @Test func developerDirectoryPrefersDEVELOPER_DIR() {
        #expect(DeveloperDirectory.resolved(environment: ["DEVELOPER_DIR": "/opt/Xcode.app/Contents/Developer"], xcodeSelect: { "/unused" }) == "/opt/Xcode.app/Contents/Developer")
        #expect(DeveloperDirectory.resolved(environment: [:], xcodeSelect: { "/Selected.xctoolchain" }) == "/Selected.xctoolchain")
    }

    @Test func jsonNullIsDistinctFromAbsentOutput() throws {
        let returnedNull = CaptureObservation(
            coordinate: .init(caseID: "null", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("x")]),
            output: .returned(.null),
            execution: .returned,
            durationMilliseconds: 1
        )
        let absent = CaptureObservation(
            coordinate: .init(caseID: "absent", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("x")]),
            output: .absent,
            execution: .threw,
            durationMilliseconds: 1,
            error: .init(kind: "subject", message: "failed")
        )
        let nullData = try CaptureJSONCoding.encoder().encode(returnedNull)
        let absentData = try CaptureJSONCoding.encoder().encode(absent)
        #expect(String(decoding: nullData, as: UTF8.self).contains("\"kind\":\"returned\""))
        #expect(String(decoding: nullData, as: UTF8.self).contains("\"value\":null"))
        #expect(String(decoding: absentData, as: UTF8.self).contains("\"kind\":\"absent\""))
        #expect(!String(decoding: absentData, as: UTF8.self).contains("\"value\":null"))
    }

    @Test func duplicateKeysAreRejected() {
        let json = Data("{\"format\":\"foundation-evals-capture\",\"format\":\"other\"}".utf8)
        #expect(throws: JSONStructureError.duplicateKey("format")) {
            try JSONStructure.validate(json, maximumDepth: 8, rejectDuplicateKeys: true)
        }
    }

    @Test func nestingInsideStringsDoesNotCountAsStructure() throws {
        let json = Data("{\"text\":\"[[[{{{{\"}".utf8)
        try JSONStructure.validate(json, maximumDepth: 2, rejectDuplicateKeys: true)
    }

    @Test func finishedManifestWithMissingObservationIsIncomplete() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = CapturePlan(cases: [
            try planCase(id: "one", text: "one"),
            try planCase(id: "two", text: "two")
        ])
        let writer = try CaptureBundleWriter(
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        try await writer.begin()
        try await writer.record(CaptureObservation(
            coordinate: .init(caseID: "one", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("one")]),
            output: .returned(.number("1")),
            execution: .returned,
            durationMilliseconds: 1
        ))
        await #expect(throws: CaptureBundleError.incompleteCannotFinish) {
            _ = try await writer.finish(state: .finished)
        }
        let url = try await writer.finish(state: .stopped)
        let bundle = try CaptureBundleValidator.load(root: url)
        #expect(bundle.coverage.isComplete == false)
        #expect(bundle.eligibility == .inspectionOnly)
    }

    @Test func extraAndDuplicateCoordinatesAreRejected() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = CapturePlan(cases: [try planCase(id: "one", text: "one")])
        let writer = try CaptureBundleWriter(
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        try await writer.begin()
        try await writer.record(CaptureObservation(
            coordinate: .init(caseID: "one", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("one")]),
            output: .returned(.number("1")),
            execution: .returned,
            durationMilliseconds: 1
        ))
        await #expect(throws: CaptureBundleError.multipleAttemptsUnsupported("one#1#default")) {
            try await writer.record(CaptureObservation(
                coordinate: .init(caseID: "one", repetition: 1),
                inputRevision: "v1",
                input: .object(["text": .string("one")]),
                output: .returned(.number("2")),
                execution: .returned,
                durationMilliseconds: 1
            ))
        }
        await #expect(throws: CaptureBundleError.extraObservation("two#1#default")) {
            try await writer.record(CaptureObservation(
                coordinate: .init(caseID: "two", repetition: 1),
                inputRevision: "v1",
                input: .object(["text": .string("two")]),
                output: .returned(.number("2")),
                execution: .returned,
                durationMilliseconds: 1
            ))
        }
    }

    @Test func jsonNumbersRoundTripWithoutBinaryFloat() throws {
        for literal in ["1000", "18446744073709551615", "-9223372036854775808", "0.5", "1e2"] {
            let value = CaptureJSON.number(literal)
            let data = try CaptureJSONCoding.encoder().encode(value)
            let decoded = try CaptureJSONCoding.decoder().decode(CaptureJSON.self, from: data)
            let parsed = try JSONStructure.decodeJSON(Data(literal.utf8))
            #expect(parsed == .number(literal))
            if case .number(let token) = decoded {
                #expect(Decimal(string: token) == Decimal(string: literal))
            } else {
                Issue.record("Expected a JSON number for \(literal).")
            }
        }
        let object = CaptureJSON.object(["total": .number("18446744073709551615")])
        let encoded = try CaptureJSONCoding.encoder().encode(object)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("1.8446744073709552e+19"))
        #expect(String(decoding: encoded, as: UTF8.self).contains("18446744073709551615"))
    }

    @Test func missingObservationsDeclarationIsRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appending(path: "empty.fevalrun", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appending(path: "observations.jsonl"))
        let manifest = CaptureManifest(
            producer: .init(appID: "example", featureID: "receipt"),
            run: .init(runID: UUID(), startedAt: .now, state: .finished),
            plan: CapturePlan(cases: []),
            files: [],
            environment: .currentHost()
        )
        try CaptureJSONCoding.encoder(prettyPrinted: true).encode(manifest)
            .write(to: root.appending(path: "manifest.json"))
        #expect(throws: CaptureBundleError.missingRequiredFile("observations.jsonl")) {
            _ = try CaptureBundleValidator.load(root: root)
        }
    }

    @Test func observationInputMustMatchThePlan() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try CaptureJSON.fromEncoded(ReceiptInput(text: "one"))
        let plan = CapturePlan(cases: [
            CapturePlanCase(caseID: "one", inputRevision: "v1", input: input)
        ])
        let writer = try CaptureBundleWriter(
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        try await writer.begin()
        try await writer.record(CaptureObservation(
            coordinate: .init(caseID: "one", repetition: 1),
            inputRevision: "v2",
            input: input,
            output: .returned(.number("1")),
            execution: .returned,
            durationMilliseconds: 1
        ))
        let url = try await writer.finish(state: .finished)
        #expect(throws: CaptureBundleError.observationPlanMismatch("one#1#default")) {
            _ = try CaptureBundleValidator.load(root: url)
        }
    }

    @Test func storageFailureDoesNotReplaceAReturnedObservation() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plan = CapturePlan(cases: [try planCase(id: "one", text: "one")])
        let writer = try CaptureBundleWriter(
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        try await writer.begin()
        let observationID = UUID()
        let input = try CaptureJSON.fromEncoded(ReceiptInput(text: "one"))
        let observationsDirectory = await writer.workingURL.appending(path: "observations")
        try FileManager.default.removeItem(at: observationsDirectory)
        try Data().write(to: observationsDirectory)
        await #expect(throws: (any Error).self) {
            try await writer.record(CaptureObservation(
                observationID: observationID,
                coordinate: .init(caseID: "one", repetition: 1),
                inputRevision: "v1",
                input: input,
                output: .returned(.number("1")),
                execution: .returned,
                durationMilliseconds: 1
            ))
        }
        #expect(await writer.recordedObservations().isEmpty)
        try FileManager.default.removeItem(at: observationsDirectory)
        try FileManager.default.createDirectory(at: observationsDirectory, withIntermediateDirectories: true)
        try await writer.record(CaptureObservation(
            observationID: observationID,
            coordinate: .init(caseID: "one", repetition: 1),
            inputRevision: "v1",
            input: input,
            output: .returned(.number("1")),
            execution: .returned,
            durationMilliseconds: 1
        ))
        await #expect(throws: CaptureBundleError.duplicateObservation(observationID.uuidString)) {
            try await writer.record(CaptureObservation(
                observationID: observationID,
                coordinate: .init(caseID: "one", repetition: 1),
                inputRevision: "v1",
                input: input,
                output: .returned(.number("2")),
                execution: .returned,
                durationMilliseconds: 1
            ))
        }
        #expect(await writer.recordedObservations().count == 1)
        #expect(await writer.recordedObservations()[0].output == .returned(.number("1")))
    }

    @Test func pathTraversalIsRejected() {
        #expect(throws: CaptureFileIOError.pathTraversal) {
            _ = try CaptureFileIO.relativePathComponents("../secret")
        }
        #expect(throws: CaptureFileIOError.pathTraversal) {
            _ = try CaptureFileIO.relativePathComponents("/tmp/x")
        }
    }

    private func run(plan: CapturePlan, in directory: URL, runID: UUID) async throws -> URL {
        let writer = try CaptureBundleWriter(
            runID: runID,
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt"),
            plan: plan,
            environment: .currentHost()
        )
        let feature = SecretInputFeature()
        return try await CaptureSession(feature: feature, writer: writer).run(plan: plan)
    }

    private func samplePlan() throws -> CapturePlan {
        CapturePlan(cases: [try planCase(id: "ordinary", text: "Example Shop")])
    }

    private func planCase(id: String, text: String) throws -> CapturePlanCase {
        CapturePlanCase(
            caseID: id,
            inputRevision: "v1",
            input: try CaptureJSON.fromEncoded(ReceiptInput(text: text))
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "capture-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
