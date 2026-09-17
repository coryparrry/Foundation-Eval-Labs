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
}
