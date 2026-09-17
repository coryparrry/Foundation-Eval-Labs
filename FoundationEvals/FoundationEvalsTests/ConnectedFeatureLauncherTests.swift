import Foundation
import FoundationEvalsIntegration
import Testing
@testable import FoundationEvals

struct ConnectedFeatureLauncherTests {
    @Test func missingCaptureIsNotSuccess() async {
        let launcher = ConnectedFeatureLauncher()
        let root = FileManager.default.temporaryDirectory.appending(path: "launcher-\(UUID().uuidString)")
        let jobID = UUID()
        let request = CaptureLaunchRequest(
            jobID: jobID,
            runID: UUID(),
            featureID: "receipt-extractor",
            planDigest: "abc",
            jobDirectoryName: jobID.uuidString,
            cases: [
                CaptureLaunchCase(caseID: "ordinary", inputRevision: "v1", input: .object(["text": .string("x")]))
            ]
        )
        try? FileManager.default.createDirectory(
            at: root.appending(path: ".foundation-evals/jobs/\(jobID.uuidString)"),
            withIntermediateDirectories: true
        )
        let authorization = ConnectedFeatureLaunchAuthorization(
            projectID: UUID(),
            projectRootPath: root.path,
            xcodeprojPath: root.appending(path: "Missing.xcodeproj").path,
            scheme: "ConnectedFeature",
            testIdentifier: "ConnectedFeatureTests/ReceiptCaptureTests",
            featureID: "receipt-extractor",
            developerDir: "/Applications/Xcode.app/Contents/Developer",
            authorizedAt: .now
        )
        await #expect(throws: ConnectedFeatureLauncherError.self) {
            _ = try await launcher.run(authorization: authorization, request: request)
        }
    }

    @Test func unexpectedJobPathIsRejected() throws {
        let jobID = UUID()
        let request = CaptureLaunchRequest(
            jobID: jobID,
            runID: UUID(),
            featureID: "receipt-extractor",
            planDigest: "abc",
            jobDirectoryName: "../escape",
            cases: []
        )
        #expect(throws: (any Error).self) {
            _ = try request.validatedJobDirectory(projectRoot: URL(filePath: "/tmp"))
        }
    }

    @Test func wrongRunOrPlanDoesNotSatisfyTheJob() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "job-verify-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = CaptureJSON.object(["text": .string("one")])
        let plan = CapturePlan(cases: [
            CapturePlanCase(caseID: "one", inputRevision: "v1", repetition: 1, featureVariant: "default", input: input)
        ])
        let runID = UUID()
        let writer = try CaptureBundleWriter(
            runID: runID,
            outputParent: directory,
            producer: .init(appID: "example", featureID: "receipt-extractor"),
            plan: plan,
            environment: .currentHost()
        )
        try await writer.begin()
        try await writer.record(CaptureObservation(
            coordinate: .init(caseID: "one", repetition: 1),
            inputRevision: "v1",
            input: input,
            output: .returned(.number("1")),
            execution: .returned,
            durationMilliseconds: 1
        ))
        let url = try await writer.finish(state: .finished)
        let bundle = try CaptureBundleValidator.load(root: url)
        let cases = plan.cases.map {
            CaptureLaunchCase(
                caseID: $0.caseID,
                inputRevision: $0.inputRevision,
                repetition: $0.repetition,
                featureVariant: $0.featureVariant,
                input: $0.input
            )
        }
        let matching = CaptureLaunchRequest(
            jobID: UUID(),
            runID: runID,
            featureID: "receipt-extractor",
            planDigest: try CapturePlanDigest.hash(cases: cases),
            jobDirectoryName: UUID().uuidString,
            cases: cases
        )
        try matching.matches(bundle: bundle)
        let wrongRun = CaptureLaunchRequest(
            jobID: matching.jobID,
            runID: UUID(),
            featureID: matching.featureID,
            planDigest: matching.planDigest,
            jobDirectoryName: matching.jobDirectoryName,
            cases: matching.cases
        )
        #expect(throws: CaptureBundleError.self) {
            try wrongRun.matches(bundle: bundle)
        }
        let wrongFeature = CaptureLaunchRequest(
            jobID: matching.jobID,
            runID: matching.runID,
            featureID: "other",
            planDigest: matching.planDigest,
            jobDirectoryName: matching.jobDirectoryName,
            cases: matching.cases
        )
        #expect(throws: CaptureBundleError.self) {
            try wrongFeature.matches(bundle: bundle)
        }
    }
}
