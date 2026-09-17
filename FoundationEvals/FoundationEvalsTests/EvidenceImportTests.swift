import Foundation
import FoundationEvalsIntegration
import Testing
@testable import FoundationEvals

@MainActor
struct EvidenceImportTests {
    @Test func validBundleImportsAsInspectionOnly() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleURL = try await writeBundle(in: directory)
        let store = EvaluationStore(supportDirectory: directory.appending(path: "store"))
        let preview = try await store.previewImportedEvidence(at: bundleURL)
        #expect(preview.warnings.contains(EvaluationImportedLabels.inspectionOnly))
        let id = try store.confirmImportedEvidence(preview)
        let run = try #require(store.run(with: id))
        #expect(run.importedEvidence?.eligibility == CaptureImportEligibility.inspectionOnly.rawValue)
        #expect(run.results.allSatisfy { $0.status == .unscored || $0.status == .error })
        let report = EvaluationReleaseCheckEvaluator.report(
            projectID: store.selectedProjectID,
            suite: store.suite,
            currentSuiteRevision: store.suiteRevision,
            run: run,
            baseline: nil,
            approvedBaseline: nil
        )
        #expect(report.outcome == .incompleteOrIncompatibleEvidence)
        #expect(report.summary == EvaluationImportedLabels.inspectionOnly)
    }

    @Test func producerRunIDDoesNotOverwriteANativeRun() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nativeID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let storeDirectory = directory.appending(path: "store")
        let store = EvaluationStore(supportDirectory: storeDirectory)
        let native = EvaluationRun(
            id: nativeID,
            suiteID: store.selectedSuiteID,
            suiteName: store.draftSuite.name,
            suiteVersion: "1",
            instructions: "",
            criteria: "",
            scoringMode: .review,
            repetitions: 1,
            startedAt: .now,
            completedAt: .now,
            cancelled: false,
            terminationReason: nil,
            environment: EvaluationEnvironment(operatingSystem: "macOS", locale: "en", model: "none", modelContextSize: 0),
            attachments: [],
            results: [
                EvaluationSampleResult(
                    id: UUID(),
                    caseID: UUID(),
                    caseName: "native",
                    repetition: 1,
                    prompt: "keep me",
                    expected: "yes",
                    response: "native-bytes",
                    status: .passed,
                    rationale: "native",
                    durationMilliseconds: 1,
                    usage: EvaluationUsage()
                )
            ],
            projectID: store.selectedProjectID
        )
        let runsDirectory = EvaluationWorkspacePersistence.suiteDirectory(
            supportDirectory: storeDirectory,
            projectID: store.selectedProjectID,
            suiteID: store.selectedSuiteID
        ).appending(path: "Runs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
        try CanonicalJSON.data(for: native).write(to: runsDirectory.appending(path: "\(nativeID.uuidString).json"))
        let bundleURL = try await writeBundle(in: directory, runID: nativeID)
        let importedID = try store.confirmImportedEvidence(try await store.previewImportedEvidence(at: bundleURL))
        #expect(importedID != nativeID)
        let nativeData = try Data(contentsOf: runsDirectory.appending(path: "\(nativeID.uuidString).json"))
        #expect(String(decoding: nativeData, as: UTF8.self).contains("native-bytes"))
        let reopened = EvaluationStore(supportDirectory: storeDirectory)
        #expect(reopened.runs.contains { $0.id == nativeID && $0.results.first?.response == "native-bytes" })
        #expect(reopened.runs.contains { $0.id == importedID && $0.importedEvidence != nil })
        let imported = try #require(reopened.run(with: importedID))
        #expect(imported.importedEvidence?.sourcePlan?.cases.count == 1)
        #expect(imported.importedEvidence?.sourcePlan?.cases.first?.repetition == 1)
        #expect(imported.importedEvidence?.sourcePlan?.cases.first?.inputRevision == "v1")
    }

    @Test func duplicateImportIsIdempotent() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleURL = try await writeBundle(in: directory)
        let store = EvaluationStore(supportDirectory: directory.appending(path: "store"))
        let first = try store.confirmImportedEvidence(try await store.previewImportedEvidence(at: bundleURL))
        let secondPreview = try await store.previewImportedEvidence(at: bundleURL)
        guard case .alreadyImported(let existing) = secondPreview.outcome else {
            Issue.record("Expected an already-imported outcome.")
            return
        }
        #expect(existing == first)
        let second = try store.confirmImportedEvidence(secondPreview)
        #expect(second == first)
        #expect(store.runs.filter { $0.id == first }.count == 1)
    }

    @Test func conflictingBytesKeepTheOriginal() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = try await writeBundle(in: directory, runID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        let store = EvaluationStore(supportDirectory: directory.appending(path: "store"))
        let first = try store.confirmImportedEvidence(try await store.previewImportedEvidence(at: firstURL))
        let original = try #require(store.run(with: first)?.results.first?.response)
        let secondURL = try await writeBundle(
            in: directory.appending(path: "second", directoryHint: .isDirectory),
            runID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            total: 750
        )
        let preview = try await store.previewImportedEvidence(at: secondURL)
        guard case .conflict = preview.outcome else {
            Issue.record("Expected a conflict for the same source run ID.")
            return
        }
        #expect(throws: EvaluationStoreError.self) {
            try store.confirmImportedEvidence(preview)
        }
        #expect(store.run(with: first)?.results.first?.response == original)
    }

    @Test func appleResultWithoutPlanHasUnknownCoverage() async throws {
        let inspection = AppleEvaluationInspection(
            resultID: UUID(),
            evaluationID: "receipt",
            evaluationInfo: [:],
            startedAt: .now,
            endedAt: .now,
            inferenceFailureCount: 1,
            evaluatorFailureCount: 1,
            failingEvaluatorTypes: ["Evaluator"],
            metricsNotFound: [],
            rowCount: 1,
            columnNames: ["response"],
            samples: [
                .init(index: 0, fields: ["response": "1000"], subjectError: nil, evaluatorError: "boom")
            ],
            originalByteCount: 12,
            digest: "abc",
            warnings: [EvaluationImportedLabels.plannedUnknown]
        )
        let run = EvidenceImportMapper.run(
            from: inspection,
            destinationProjectID: UUID(),
            destinationSuiteID: UUID(),
            suiteName: "Imported"
        )
        #expect(run.importedEvidence?.coverageLabel == EvaluationImportedLabels.plannedUnknown)
        #expect(run.plannedSampleCount == nil)
        #expect(run.results[0].judgeErrorCategory == "evaluator")
        #expect(run.results[0].status == EvaluationResultStatus.unscored)
        #expect(run.importedEvidence?.originalRelativePath == "")
        #expect(run.importedEvidence?.checks.contains { $0.name == "paidTotal" && $0.value != nil } == false)
    }

    @Test func claimedApprovalDoesNotPassRelease() {
        var run = EvaluationRun(
            id: UUID(),
            suiteID: UUID(),
            suiteName: "Imported",
            suiteVersion: "imported",
            instructions: "",
            criteria: "",
            scoringMode: .review,
            repetitions: 1,
            startedAt: .now,
            completedAt: .now,
            cancelled: false,
            terminationReason: nil,
            environment: EvaluationEnvironment(operatingSystem: "macOS", locale: "en", model: "none", modelContextSize: 0),
            attachments: [],
            results: []
        )
        run.importedEvidence = EvaluationImportedEvidence(
            sourceKind: .captureBundle,
            eligibility: "inspectionOnly",
            producerAppID: "x",
            producerFeatureID: "y",
            producerRunID: "z",
            sourceDigest: "1",
            manifestDigest: "1",
            importedAt: .now,
            captureStartedAt: nil,
            captureEndedAt: nil,
            warnings: [],
            coverageLabel: "complete",
            environmentClaims: [:],
            importerHost: [:],
            originalRelativePath: "imported",
            rerunOf: nil,
            sourceCaseIDs: [:],
            transcriptAvailable: false,
            checks: []
        )
        let suite = EvaluationSuite()
        let report = EvaluationReleaseCheckEvaluator.report(
            projectID: UUID(),
            suite: suite,
            currentSuiteRevision: "rev",
            run: run,
            baseline: nil,
            approvedBaseline: nil
        )
        #expect(report.outcome == .incompleteOrIncompatibleEvidence)
    }

    @Test func pathTraversalIsRejected() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hostile = directory.appending(path: "hostile.fevalrun", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: hostile, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: hostile.appending(path: "manifest.json"))
        let link = hostile.appending(path: "escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory.appending(path: "secret.json"))
        let store = EvaluationStore(supportDirectory: directory.appending(path: "store"))
        await #expect(throws: CaptureFileIOError.self) {
            _ = try await store.previewImportedEvidence(at: hostile)
        }
        #expect(store.runs.isEmpty)
    }

    @Test func destinationStaysBoundAfterProjectSwitch() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleURL = try await writeBundle(in: directory)
        let store = EvaluationStore(supportDirectory: directory.appending(path: "store"))
        let preview = try await store.previewImportedEvidence(at: bundleURL)
        let originalProject = preview.destinationProjectID
        _ = try store.createProject(name: "Other")
        let id = try store.confirmImportedEvidence(preview)
        #expect(store.run(with: id)?.projectID == originalProject)
    }

    @Test func appleSavedJSONKeepsSampleDistinctions() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "my-export.json")
        try appleFixtureJSON().write(to: url)
        let store = EvaluationStore(supportDirectory: directory.appending(path: "store"))
        let preview = try await store.previewImportedEvidence(at: url)
        #expect(preview.sampleCount == 4)
        #expect(preview.canNormalize)
        let id = try store.confirmImportedEvidence(preview)
        let run = try #require(store.run(with: id))
        #expect(run.results.count == 4)
        #expect(run.results.contains { $0.errorCategory == "subject" })
        #expect(run.results.contains { $0.judgeErrorCategory == "evaluator" })
        #expect(run.importedEvidence?.checks.contains { $0.name == "paidTotal" && $0.status == "fail" } == true)
        #expect(run.importedEvidence?.checks.contains { $0.name == "penceScale" && $0.value == "99" } == true)
        #expect(run.importedEvidence?.originalRelativePath == "imported/my-export.json")
        let reopened = EvaluationStore(supportDirectory: directory.appending(path: "store"))
        let restored = try #require(reopened.run(with: id))
        #expect(restored.results.count == 4)
        #expect(restored.importedEvidence?.checks.contains { $0.status == "ignore" } == true)
        #expect(restored.importedEvidence?.originalRelativePath == "imported/my-export.json")
    }

    @Test func emptyDirectoryTreeIsRejected() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appending(path: "empty-tree.fevalrun", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<CaptureLimits.version1.maximumVisitedEntries {
            try FileManager.default.createDirectory(
                at: root.appending(path: "d\(index)", directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
        let store = EvaluationStore(supportDirectory: directory.appending(path: "store"))
        await #expect(throws: CaptureFileIOError.self) {
            _ = try await store.previewImportedEvidence(at: root)
        }
    }

    @Test func captureErrorAndPartialOutputAreInspectable() throws {
        let observation = CaptureObservation(
            coordinate: .init(caseID: "partial", repetition: 1),
            inputRevision: "v1",
            input: .object(["text": .string("hello")]),
            output: .absent,
            execution: .returned,
            durationMilliseconds: 12,
            captureError: .init(kind: "serializationFailed", message: "could not encode"),
            partialOutput: .string("hel"),
            checks: [
                CaptureCheck(
                    id: "scale",
                    name: "penceScale",
                    status: .unknown,
                    semantics: "score",
                    value: .number("99"),
                    evaluator: "custom"
                )
            ]
        )
        let plan = CapturePlan(cases: [
            CapturePlanCase(caseID: "partial", inputRevision: "v1", input: .object(["text": .string("hello")]))
        ])
        let bundle = CaptureBundle(
            root: URL(filePath: "/tmp"),
            manifest: CaptureManifest(
                producer: .init(appID: "example", featureID: "receipt-extractor"),
                run: CaptureRunRecord(runID: UUID(), rerunOf: nil, startedAt: .now, endedAt: .now, state: .finished),
                plan: plan,
                files: [],
                environment: .currentHost()
            ),
            observations: [observation],
            expectations: [],
            coverage: .reconcile(plan: plan, observations: [observation]),
            eligibility: .inspectionOnly,
            warnings: [],
            manifestDigest: "abc"
        )
        let run = try EvidenceImportMapper.run(
            from: bundle,
            destinationProjectID: UUID(),
            destinationSuiteID: UUID(),
            suiteName: "Imported"
        )
        #expect(run.results[0].response == "hel")
        #expect(run.results[0].errorCategory == "serializationFailed")
        #expect(run.importedEvidence?.sampleNotes?.first?.partialOutput != nil)
        #expect(run.importedEvidence?.checks.first?.value == "99")
        #expect(run.importedEvidence?.checks.first?.evaluator == "custom")
    }

    private func writeBundle(in directory: URL, runID: UUID = UUID(), total: Int = 1000) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = try CaptureJSON.fromEncoded(["text": "Example Shop\nTotal paid: GBP 7.50"])
        let plan = CapturePlan(cases: [
            CapturePlanCase(caseID: "discounted", inputRevision: "v1", input: input)
        ])
        let writer = try CaptureBundleWriter(
            runID: runID,
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt-extractor"),
            plan: plan,
            environment: .currentHost()
        )
        try await writer.begin()
        try await writer.record(
            CaptureObservation(
                coordinate: .init(caseID: "discounted", repetition: 1),
                inputRevision: "v1",
                input: input,
                output: .returned(.object(["totalPence": .number(String(total))])),
                execution: .returned,
                durationMilliseconds: 1,
                checks: [
                    CaptureCheck(
                        id: "paid-total",
                        name: "paid total",
                        status: total == 750 ? .passed : .failed,
                        semantics: "Producer-reported"
                    )
                ]
            )
        )
        return try await writer.finish(state: .finished)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "evidence-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func appleFixtureJSON() -> Data {
        Data(
            """
            {
              "resultID": "19EE78CD-9DEE-4182-9681-43DA7D674255",
              "evaluationID": "ReceiptNativeEvaluation",
              "evaluationInfo": { "fixture": "controlled-receipt" },
              "startTime": "2026-09-17T19:17:18Z",
              "endTime": "2026-09-17T19:17:18Z",
              "runErrors": {
                "inferenceFailureCount": 1,
                "evaluatorFailureCount": 1,
                "failingEvaluatorTypes": ["Evaluator"],
                "metricsNotFound": []
              },
              "reportMetadata": { "ColumnOrdering": ["Input", "Response", "Expected", "SubjectInferenceError", "EvaluatorErrors", "paidTotal", "ignoredDemo", "penceScale"] },
              "results": [
                {
                  "Input": "{\\"input\\":{\\"prompt\\":\\"ordinary\\"}}",
                  "Response": { "typeName": "ReceiptOutput", "value": "{\\"totalPence\\":1000}" },
                  "Expected": "{\\"totalPence\\":1000}",
                  "SubjectInferenceError": null,
                  "EvaluatorErrors": null,
                  "paidTotal": { "kind": "pass", "value": true, "rationale": "matched", "evaluatorKind": "custom" },
                  "ignoredDemo": { "kind": "ignore", "value": null, "rationale": "Check ignored · Not evidence of a pass" },
                  "penceScale": { "kind": "score", "value": 99, "rationale": "Pence scale; not a 1-4 rubric", "evaluatorKind": "custom" }
                },
                {
                  "Input": "{\\"input\\":{\\"prompt\\":\\"discounted\\"}}",
                  "Response": { "value": "{\\"totalPence\\":1000}" },
                  "Expected": "{\\"totalPence\\":750}",
                  "SubjectInferenceError": null,
                  "EvaluatorErrors": null,
                  "paidTotal": { "kind": "fail", "value": false, "rationale": "1000 != 750" },
                  "ignoredDemo": { "kind": "ignore", "rationale": "Check ignored · Not evidence of a pass" },
                  "penceScale": { "kind": "score", "value": 99 }
                },
                {
                  "Input": "{\\"input\\":{\\"prompt\\":\\"SUBJECT_THROW\\"}}",
                  "Response": null,
                  "Expected": "{}",
                  "SubjectInferenceError": "The receipt has no shop name.",
                  "EvaluatorErrors": null,
                  "paidTotal": { "kind": "ignore", "rationale": "No inference was produced" }
                },
                {
                  "Input": "{\\"input\\":{\\"prompt\\":\\"EVALUATOR_THROW\\"}}",
                  "Response": { "value": "{\\"totalPence\\":100}" },
                  "Expected": "{}",
                  "SubjectInferenceError": null,
                  "EvaluatorErrors": ["The receipt has no total."],
                  "paidTotal": { "kind": "ignore", "rationale": "No inference was produced" },
                  "penceScale": { "kind": "score", "value": 99 }
                }
              ]
            }
            """.utf8
        )
    }
}
