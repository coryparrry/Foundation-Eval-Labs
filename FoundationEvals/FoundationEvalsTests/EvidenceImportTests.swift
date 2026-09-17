import Foundation
import FoundationEvalsAppleBridge
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
}
