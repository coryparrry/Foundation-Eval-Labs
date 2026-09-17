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

    public func matches(bundle: CaptureBundle) throws {
        guard bundle.manifest.run.runID == runID else {
            throw CaptureBundleError.invalidControlDocument("Returned run ID does not match the request.")
        }
        guard bundle.manifest.producer.featureID == featureID else {
            throw CaptureBundleError.invalidControlDocument("Returned feature ID does not match the request.")
        }
        let actual = bundle.manifest.plan.cases.map {
            CaptureLaunchCase(
                caseID: $0.caseID,
                inputRevision: $0.inputRevision,
                repetition: $0.repetition,
                featureVariant: $0.featureVariant,
                input: $0.input
            )
        }
        let digest = try CapturePlanDigest.hash(cases: actual)
        guard digest == planDigest, digest == (try CapturePlanDigest.hash(cases: cases)) else {
            throw CaptureBundleError.invalidControlDocument("Returned plan does not match the request.")
        }
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
