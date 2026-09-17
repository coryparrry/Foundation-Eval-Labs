import Foundation

public struct CaptureCheck: Sendable, Equatable, Codable {
    public var id: String
    public var name: String
    public var status: CaptureCheckStatus
    public var semantics: String
    public var value: CaptureJSON?
    public var rationale: String?
    public var evaluator: String?

    public init(
        id: String,
        name: String,
        status: CaptureCheckStatus,
        semantics: String,
        value: CaptureJSON? = nil,
        rationale: String? = nil,
        evaluator: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.semantics = semantics
        self.value = value
        self.rationale = rationale
        self.evaluator = evaluator
    }
}

public struct CaptureErrorRecord: Sendable, Equatable, Codable {
    public var kind: String
    public var message: String

    public init(kind: String, message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct CaptureObservation: Sendable, Equatable, Codable {
    public var observationID: UUID
    public var attemptID: UUID
    public var coordinate: CaptureCoordinate
    public var inputRevision: String
    public var input: CaptureJSON
    public var output: CaptureOutput
    public var execution: CaptureExecutionOutcome
    public var durationMilliseconds: Double
    public var error: CaptureErrorRecord?
    public var evaluatorError: CaptureErrorRecord?
    public var captureError: CaptureErrorRecord?
    public var transcriptError: CaptureErrorRecord?
    public var partialOutput: CaptureJSON?
    public var checks: [CaptureCheck]
    public var transcriptRelativePath: String?

    public init(
        observationID: UUID = UUID(),
        attemptID: UUID = UUID(),
        coordinate: CaptureCoordinate,
        inputRevision: String,
        input: CaptureJSON,
        output: CaptureOutput,
        execution: CaptureExecutionOutcome,
        durationMilliseconds: Double,
        error: CaptureErrorRecord? = nil,
        evaluatorError: CaptureErrorRecord? = nil,
        captureError: CaptureErrorRecord? = nil,
        transcriptError: CaptureErrorRecord? = nil,
        partialOutput: CaptureJSON? = nil,
        checks: [CaptureCheck] = [],
        transcriptRelativePath: String? = nil
    ) {
        self.observationID = observationID
        self.attemptID = attemptID
        self.coordinate = coordinate
        self.inputRevision = inputRevision
        self.input = input
        self.output = output
        self.execution = execution
        self.durationMilliseconds = durationMilliseconds
        self.error = error
        self.evaluatorError = evaluatorError
        self.captureError = captureError
        self.transcriptError = transcriptError
        self.partialOutput = partialOutput
        self.checks = checks
        self.transcriptRelativePath = transcriptRelativePath
    }
}

public struct CaptureCoverage: Sendable, Equatable {
    public var plannedCount: Int
    public var observedCount: Int
    public var missingCoordinates: [CaptureCoordinate]
    public var extraCoordinates: [CaptureCoordinate]
    public var isComplete: Bool { missingCoordinates.isEmpty && extraCoordinates.isEmpty }

    public static func reconcile(plan: CapturePlan, observations: [CaptureObservation]) -> CaptureCoverage {
        let planned = plan.coordinates
        let observed = observations.map(\.coordinate)
        let missing = planned.filter { coordinate in !observed.contains(coordinate) }
        let extra = observed.filter { coordinate in !planned.contains(coordinate) }
        return CaptureCoverage(
            plannedCount: planned.count,
            observedCount: observed.count,
            missingCoordinates: missing,
            extraCoordinates: extra
        )
    }
}
