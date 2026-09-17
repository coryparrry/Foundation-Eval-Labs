import Foundation

public enum CaptureFormat {
    public static let name = "foundation-evals-capture"
    public static let version = 1
}

public enum CaptureRunState: String, Sendable, Codable, Equatable {
    case running
    case finished
    case stopped
    case cancelled
}

public enum CaptureExecutionOutcome: String, Sendable, Codable, Equatable {
    case returned
    case threw
    case cancelled
}

public enum CaptureCheckStatus: String, Sendable, Codable, Equatable {
    case passed
    case failed
    case ignored
    case error
    case unknown
}

public enum CaptureImportEligibility: String, Sendable, Codable, Equatable {
    case ready
    case inspectionOnly
    case rejected
}

public struct CaptureCoordinate: Sendable, Hashable, Codable, Equatable {
    public var caseID: String
    public var repetition: Int
    public var featureVariant: String

    public init(caseID: String, repetition: Int, featureVariant: String = "default") {
        self.caseID = caseID
        self.repetition = repetition
        self.featureVariant = featureVariant
    }

    public var identity: String { "\(caseID)#\(repetition)#\(featureVariant)" }
}

public struct CaptureProducer: Sendable, Equatable, Codable {
    public var integrationVersion: String
    public var bridgeVersion: String?
    public var appID: String
    public var featureID: String

    public init(
        integrationVersion: String = "1.0.0",
        bridgeVersion: String? = nil,
        appID: String,
        featureID: String
    ) {
        self.integrationVersion = integrationVersion
        self.bridgeVersion = bridgeVersion
        self.appID = appID
        self.featureID = featureID
    }
}

public struct CaptureRunRecord: Sendable, Equatable, Codable {
    public var runID: UUID
    public var rerunOf: UUID?
    public var startedAt: Date
    public var endedAt: Date?
    public var state: CaptureRunState

    public init(
        runID: UUID,
        rerunOf: UUID? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        state: CaptureRunState
    ) {
        self.runID = runID
        self.rerunOf = rerunOf
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.state = state
    }
}

public struct CapturePlanCase: Sendable, Equatable, Codable {
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

    public var coordinate: CaptureCoordinate {
        CaptureCoordinate(caseID: caseID, repetition: repetition, featureVariant: featureVariant)
    }
}

public struct CapturePlan: Sendable, Equatable, Codable {
    public var cases: [CapturePlanCase]

    public init(cases: [CapturePlanCase]) {
        self.cases = cases
    }

    public var coordinates: [CaptureCoordinate] { cases.map(\.coordinate) }
}

public struct CaptureEnvironment: Sendable, Equatable, Codable {
    public var operatingSystem: String
    public var locale: String
    public var device: String?
    public var sourceRevision: String?
    public var workingTreeDirty: Bool?
    public var featureConfigurationID: String?
    public var model: String?
    public var unknowns: [String]

    public init(
        operatingSystem: String,
        locale: String,
        device: String? = nil,
        sourceRevision: String? = nil,
        workingTreeDirty: Bool? = nil,
        featureConfigurationID: String? = nil,
        model: String? = nil,
        unknowns: [String] = []
    ) {
        self.operatingSystem = operatingSystem
        self.locale = locale
        self.device = device
        self.sourceRevision = sourceRevision
        self.workingTreeDirty = workingTreeDirty
        self.featureConfigurationID = featureConfigurationID
        self.model = model
        self.unknowns = unknowns
    }

    public static func currentHost(featureConfigurationID: String? = nil, model: String? = nil) -> CaptureEnvironment {
        CaptureEnvironment(
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            locale: Locale.current.identifier,
            device: nil,
            sourceRevision: nil,
            workingTreeDirty: nil,
            featureConfigurationID: featureConfigurationID,
            model: model,
            unknowns: ["sourceRevision", "workingTreeDirty", "device"].filter { _ in true }
        )
    }
}

public enum CaptureFileKind: String, Sendable, Codable, Equatable {
    case manifest
    case observations
    case expectations
    case appleResult
    case transcript
    case attachment
}

public struct CaptureFileEntry: Sendable, Equatable, Codable {
    public var relativePath: String
    public var byteCount: Int
    public var sha256: String
    public var kind: CaptureFileKind

    public init(relativePath: String, byteCount: Int, sha256: String, kind: CaptureFileKind) {
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.sha256 = sha256
        self.kind = kind
    }
}

public struct CaptureManifest: Sendable, Equatable, Codable {
    public var format: String
    public var formatVersion: Int
    public var producer: CaptureProducer
    public var run: CaptureRunRecord
    public var plan: CapturePlan
    public var files: [CaptureFileEntry]
    public var environment: CaptureEnvironment

    public init(
        format: String = CaptureFormat.name,
        formatVersion: Int = CaptureFormat.version,
        producer: CaptureProducer,
        run: CaptureRunRecord,
        plan: CapturePlan,
        files: [CaptureFileEntry],
        environment: CaptureEnvironment
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.producer = producer
        self.run = run
        self.plan = plan
        self.files = files
        self.environment = environment
    }
}

public struct CaptureExpectation: Sendable, Equatable, Codable {
    public var caseID: String
    public var inputRevision: String
    public var expected: CaptureJSON
    public var reviewProvenance: String?

    public init(caseID: String, inputRevision: String, expected: CaptureJSON, reviewProvenance: String? = nil) {
        self.caseID = caseID
        self.inputRevision = inputRevision
        self.expected = expected
        self.reviewProvenance = reviewProvenance
    }
}
