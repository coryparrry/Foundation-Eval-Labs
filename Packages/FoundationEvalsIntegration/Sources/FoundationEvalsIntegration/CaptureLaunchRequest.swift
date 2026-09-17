import Foundation

public struct CaptureLaunchCase: Sendable, Equatable, Codable {
    public var caseID: String
    public var inputRevision: String
    public var repetition: Int
    public var featureVariant: String
    public var input: CaptureJSON

    public init(
        caseID: String,
        inputRevision: String,
        repetition: Int = 1,
        featureVariant: String = "default",
        input: CaptureJSON
    ) {
        self.caseID = caseID
        self.inputRevision = inputRevision
        self.repetition = repetition
        self.featureVariant = featureVariant
        self.input = input
    }
}

/// Project-owned launcher request. Contains no expected answers, executable path, or shell command.
public struct CaptureLaunchRequest: Sendable, Equatable, Codable {
    public var jobID: UUID
    public var runID: UUID
    public var featureID: String
    public var parentRunID: UUID?
    public var planDigest: String
    public var jobDirectoryName: String
    public var cases: [CaptureLaunchCase]

    public init(
        jobID: UUID,
        runID: UUID,
        featureID: String,
        parentRunID: UUID? = nil,
        planDigest: String,
        jobDirectoryName: String,
        cases: [CaptureLaunchCase]
    ) {
        self.jobID = jobID
        self.runID = runID
        self.featureID = featureID
        self.parentRunID = parentRunID
        self.planDigest = planDigest
        self.jobDirectoryName = jobDirectoryName
        self.cases = cases
    }

    public func validatedJobDirectory(projectRoot: URL) throws -> URL {
        let jobs = projectRoot
            .appending(path: ".foundation-evals", directoryHint: .isDirectory)
            .appending(path: "jobs", directoryHint: .isDirectory)
        let job = try CaptureFileIO.resolvedMember(root: jobs, relativePath: jobDirectoryName)
        guard job.lastPathComponent == jobID.uuidString else {
            throw CaptureBundleError.invalidControlDocument("Job directory does not match the request job ID.")
        }
        return job
    }
}

public enum CapturePlanDigest {
    public static func hash(cases: [CaptureLaunchCase]) throws -> String {
        CaptureDigest.sha256Hex(try CaptureJSONCoding.encoder().encode(cases))
    }
}
