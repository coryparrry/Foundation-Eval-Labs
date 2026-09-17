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
