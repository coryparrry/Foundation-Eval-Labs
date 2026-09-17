import Foundation
import FoundationEvalsIntegration

struct ConnectedFeatureLaunchAuthorization: Codable, Equatable, Sendable {
    var projectID: UUID
    var projectRootPath: String
    var xcodeprojPath: String
    var scheme: String
    var testIdentifier: String
    var featureID: String
    var developerDir: String
    var authorizedAt: Date
}

enum ConnectedFeatureLauncherState: Equatable, Sendable {
    case idle
    case launching
    case running
    case stopping
    case unresolvedStop
    case failed(String)
}

actor ConnectedFeatureLauncher {
    private var process: Process?
    private var unresolved = false

    func run(authorization: ConnectedFeatureLaunchAuthorization, request: CaptureLaunchRequest) async throws -> URL {
        if unresolved {
            throw ConnectedFeatureLauncherError.unresolvedStop
        }
        if process?.isRunning == true {
            throw ConnectedFeatureLauncherError.busy
        }
        let projectRoot = URL(filePath: authorization.projectRootPath, directoryHint: .isDirectory)
        let job = try request.validatedJobDirectory(projectRoot: projectRoot)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: true)
        let handoff = projectRoot.appending(path: ".foundation-evals", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
        let requestURL = handoff.appending(path: "request.json")
        try CaptureFileIO.writeAtomically(try CaptureJSONCoding.encoder(prettyPrinted: true).encode(request), to: requestURL)

        let xcodebuild = URL(filePath: authorization.developerDir).appending(path: "usr/bin/xcodebuild")
        let resultBundle = job.appending(path: "test-results.xcresult")
        let child = Process()
        child.executableURL = xcodebuild
        child.currentDirectoryURL = projectRoot
        child.arguments = [
            "-project", authorization.xcodeprojPath,
            "-scheme", authorization.scheme,
            "-destination", "platform=macOS",
            "-only-testing:\(authorization.testIdentifier)",
            "-resultBundlePath", resultBundle.path,
            "test",
        ]
        child.environment = [
            "DEVELOPER_DIR": authorization.developerDir,
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
        ]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        child.standardOutput = outputPipe
        child.standardError = errorPipe
        process = child
        try child.run()
        let logs = await drain(output: outputPipe, error: errorPipe, limit: CaptureLimits.version1.maximumLauncherLogBytes)
        child.waitUntilExit()
        process = nil
        let status = child.terminationStatus
        let published = try FileManager.default.contentsOfDirectory(
            at: job,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ).first { $0.pathExtension == "fevalrun" }
        guard let published else {
            if status == 0 {
                throw ConnectedFeatureLauncherError.missingCapture
            }
            throw ConnectedFeatureLauncherError.processFailed(status: status, log: logs)
        }
        return published
    }

    func requestStop() -> ConnectedFeatureLauncherState {
        process?.terminate()
        return .stopping
    }

    func waitForStop(timeout: Duration) async -> ConnectedFeatureLauncherState {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if process?.isRunning != true {
                process = nil
                return .idle
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        if process?.isRunning == true {
            unresolved = true
            return .unresolvedStop
        }
        process = nil
        return .idle
    }

    private func drain(output: Pipe, error: Pipe, limit: Int) async -> String {
        await withTaskGroup(of: Data.self) { group in
            group.addTask { readLimited(from: output.fileHandleForReading, limit: limit) }
            group.addTask { readLimited(from: error.fileHandleForReading, limit: limit) }
            var combined = Data()
            for await chunk in group {
                if combined.count >= limit { continue }
                let allowed = min(limit - combined.count, chunk.count)
                combined.append(chunk.prefix(allowed))
            }
            return String(decoding: combined.suffix(8_192), as: UTF8.self)
        }
    }
}

enum ConnectedFeatureLauncherError: LocalizedError {
    case busy
    case unresolvedStop
    case missingCapture
    case processFailed(status: Int32, log: String)
    case unauthorized
    case incompatibleEvidence

    var errorDescription: String? {
        switch self {
        case .busy: "A connected-feature rerun is already running."
        case .unresolvedStop: "The previous test process did not stop. Resolve that before starting another run."
        case .missingCapture: "The test finished without writing capture evidence."
        case .processFailed(let status, let log):
            "The connected test exited \(status). \(log)"
        case .unauthorized: "Authorize the Connected Feature example before rerunning it."
        case .incompatibleEvidence: "This evidence cannot be rerun from Foundation Evals."
        }
    }
}

private func readLimited(from handle: FileHandle, limit: Int) -> Data {
    var data = Data()
    while true {
        let chunk = handle.availableData
        if chunk.isEmpty { break }
        if data.count < limit {
            let allowed = min(limit - data.count, chunk.count)
            data.append(chunk.prefix(allowed))
        }
    }
    return data
}
