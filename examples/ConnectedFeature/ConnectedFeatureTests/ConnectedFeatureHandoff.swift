import Foundation
import FoundationEvalsIntegration

enum ConnectedFeatureHandoff {
    static var projectRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var handoffDirectory: URL {
        projectRoot.appending(path: ".foundation-evals", directoryHint: .isDirectory)
    }

    static var requestURL: URL {
        handoffDirectory.appending(path: "request.json")
    }

    static func loadRequestSnapshot() throws -> CaptureLaunchRequest? {
        guard FileManager.default.fileExists(atPath: requestURL.path) else { return nil }
        let data = try CaptureFileIO.readRegularFileNoFollow(
            at: requestURL,
            maximumBytes: CaptureLimits.version1.maximumManifestBytes
        )
        try JSONStructure.validate(data, maximumDepth: CaptureLimits.version1.maximumJSONNestingDepth, rejectDuplicateKeys: true)
        let request = try CaptureJSONCoding.decoder().decode(CaptureLaunchRequest.self, from: data)
        _ = try request.validatedJobDirectory(projectRoot: projectRoot)
        return request
    }
}
