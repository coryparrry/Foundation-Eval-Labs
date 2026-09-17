import Foundation

public enum CaptureBundleError: Error, Equatable, LocalizedError {
    case unsupportedFormat(String)
    case unsupportedVersion(Int)
    case planTooLarge(maximum: Int)
    case duplicateCoordinate(String)
    case multipleAttemptsUnsupported(String)
    case extraObservation(String)
    case missingObservation(String)
    case duplicateObservation(String)
    case observationPlanMismatch(String)
    case missingRequiredFile(String)
    case conflictingFiles
    case incompleteCannotFinish
    case alreadyPublished
    case captureFailed(String)
    case invalidControlDocument(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format): "Unsupported capture format \"\(format)\"."
        case .unsupportedVersion(let version): "Unsupported capture format version \(version)."
        case .planTooLarge(let maximum): "A capture can plan at most \(maximum) trials."
        case .duplicateCoordinate(let id): "Duplicate planned coordinate \(id)."
        case .multipleAttemptsUnsupported(let id): "Version 1 does not allow multiple attempts for \(id)."
        case .extraObservation(let id): "Observation \(id) is not in the frozen plan."
        case .missingObservation(let id): "Planned coordinate \(id) has no observation."
        case .duplicateObservation(let id): "Observation \(id) is duplicated."
        case .observationPlanMismatch(let id): "Observation \(id) does not match the frozen plan."
        case .missingRequiredFile(let path): "The capture is missing required file \(path)."
        case .conflictingFiles: "The bundle contains conflicting file entries."
        case .incompleteCannotFinish: "A finished bundle cannot omit planned observations."
        case .alreadyPublished: "A capture folder with this run ID already exists."
        case .captureFailed(let message): message
        case .invalidControlDocument(let message): message
        }
    }
}

public struct CaptureRecoveryReport: Sendable, Equatable {
    public var completeObservations: [CaptureObservation]
    public var unfinishedPresent: Bool
    public var canClaimFinished: Bool { false }
}

public actor CaptureBundleWriter {
    private let limits: CaptureLimits
    private let producer: CaptureProducer
    private let plan: CapturePlan
    private let environment: CaptureEnvironment
    private let workingDirectory: URL
    private let publishedDirectory: URL
    private var run: CaptureRunRecord
    private var observations: [UUID: CaptureObservation] = [:]
    private var rawFiles: [(relativePath: String, data: Data, kind: CaptureFileKind)] = []
    private var expectations: [CaptureExpectation]
    private var finalized = false
    private var observationBytes = 0
    private var rawBytes = 0

    public func recordedObservations() -> [CaptureObservation] {
        observations.values.sorted { $0.coordinate.identity < $1.coordinate.identity }
    }

    public init(
        runID: UUID = UUID(),
        rerunOf: UUID? = nil,
        outputParent: URL,
        limits: CaptureLimits = .version1,
        producer: CaptureProducer,
        plan: CapturePlan,
        environment: CaptureEnvironment,
        expectations: [CaptureExpectation] = []
    ) throws {
        self.limits = limits
        self.producer = producer
        self.plan = plan
        self.environment = environment
        self.expectations = expectations
        try Self.validatePlan(plan, limits: limits)
        run = CaptureRunRecord(runID: runID, rerunOf: rerunOf, startedAt: Date(), state: .running)
        workingDirectory = outputParent.appending(
            path: ".\(runID.uuidString).fevalrun.working-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        publishedDirectory = outputParent.appending(path: "\(runID.uuidString).fevalrun", directoryHint: .isDirectory)
    }

    public var runID: UUID { run.runID }
    public var workingURL: URL { workingDirectory }

    public func begin() throws {
        if FileManager.default.fileExists(atPath: publishedDirectory.path) {
            throw CaptureBundleError.alreadyPublished
        }
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: workingDirectory.appending(path: "observations", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: workingDirectory.appending(path: "raw", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try writePlanAndState()
    }

    public func record(_ observation: CaptureObservation) throws {
        try validate(observation)
        if observations[observation.observationID] != nil {
            throw CaptureBundleError.duplicateObservation(observation.observationID.uuidString)
        }
        let data = try CaptureJSONCoding.encoder().encode(observation)
        try checkPublishedBudget(observationBytes: observationBytes + data.count, extraFiles: 0, extraBytes: 0)
        try CaptureFileIO.writeAtomically(
            data,
            to: workingDirectory.appending(path: "observations/\(observation.observationID.uuidString).json")
        )
        observationBytes += data.count
        observations[observation.observationID] = observation
    }

    public func attachRaw(relativePath: String, data: Data, kind: CaptureFileKind) throws {
        _ = try CaptureFileIO.relativePathComponents(relativePath)
        if kind == .appleResult || kind == .transcript {
            guard data.count <= limits.maximumAppleJSONBytes else {
                throw CaptureFileIOError.tooLarge(maximumBytes: limits.maximumAppleJSONBytes)
            }
        }
        try checkPublishedBudget(observationBytes: observationBytes, extraFiles: 1, extraBytes: data.count)
        rawFiles.append((relativePath, data, kind))
        rawBytes += data.count
        try CaptureFileIO.writeAtomically(data, to: workingDirectory.appending(path: relativePath))
    }

    public func finish(state: CaptureRunState) throws -> URL {
        guard !finalized else { throw CaptureBundleError.alreadyPublished }
        if state == .finished {
            let coverage = CaptureCoverage.reconcile(plan: plan, observations: Array(observations.values))
            if !coverage.isComplete { throw CaptureBundleError.incompleteCannotFinish }
        }
        run.endedAt = Date()
        run.state = state
        try publish()
        finalized = true
        return publishedDirectory
    }

    public func cancel() throws -> URL {
        try finish(state: .cancelled)
    }

    public static func inspectWorkingDirectory(_ url: URL, limits: CaptureLimits = .version1) throws -> CaptureRecoveryReport {
        let observationsDirectory = url.appending(path: "observations", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: observationsDirectory.path) else {
            return CaptureRecoveryReport(completeObservations: [], unfinishedPresent: true)
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: observationsDirectory, includingPropertiesForKeys: nil)) ?? []
        var complete: [CaptureObservation] = []
        var unfinished = false
        for file in files where file.pathExtension == "json" {
            do {
                let data = try CaptureFileIO.readRegularFileNoFollow(at: file, maximumBytes: limits.maximumObservationLineBytes)
                complete.append(try CaptureJSONCoding.decoder().decode(CaptureObservation.self, from: data))
            } catch {
                unfinished = true
            }
        }
        return CaptureRecoveryReport(completeObservations: complete, unfinishedPresent: unfinished)
    }

    private func publish() throws {
        if FileManager.default.fileExists(atPath: publishedDirectory.path) {
            throw CaptureBundleError.alreadyPublished
        }
        let ordered = observations.values.sorted {
            $0.coordinate.identity < $1.coordinate.identity
        }
        var jsonl = Data()
        for observation in ordered {
            let line = try CaptureJSONCoding.encoder().encode(observation)
            guard line.count <= limits.maximumObservationLineBytes else {
                throw CaptureFileIOError.tooLarge(maximumBytes: limits.maximumObservationLineBytes)
            }
            jsonl.append(line)
            jsonl.append(UInt8(ascii: "\n"))
        }
        try CaptureFileIO.writeAtomically(jsonl, to: workingDirectory.appending(path: "observations.jsonl"))
        try checkPublishedBudget(observationBytes: jsonl.count, extraFiles: 0, extraBytes: 0)

        var files: [CaptureFileEntry] = []
        files.append(try fileEntry("observations.jsonl", kind: .observations))
        if !expectations.isEmpty {
            let data = try CaptureJSONCoding.encoder(prettyPrinted: true).encode(expectations)
            try checkPublishedBudget(observationBytes: jsonl.count, extraFiles: 1, extraBytes: data.count)
            try CaptureFileIO.writeAtomically(data, to: workingDirectory.appending(path: "expectations.json"))
            files.append(try fileEntry("expectations.json", kind: .expectations))
        }
        for raw in rawFiles {
            files.append(try fileEntry(raw.relativePath, kind: raw.kind))
        }

        let uniquePaths = Set(files.map(\.relativePath))
        guard uniquePaths.count == files.count else { throw CaptureBundleError.conflictingFiles }

        let manifest = CaptureManifest(
            producer: producer,
            run: run,
            plan: plan,
            files: files,
            environment: environment
        )
        let manifestData = try CaptureJSONCoding.encoder(prettyPrinted: true).encode(manifest)
        guard manifestData.count <= limits.maximumManifestBytes else {
            throw CaptureFileIOError.tooLarge(maximumBytes: limits.maximumManifestBytes)
        }
        try JSONStructure.validate(
            manifestData,
            maximumDepth: limits.maximumJSONNestingDepth,
            rejectDuplicateKeys: true
        )
        try CaptureFileIO.writeAtomically(manifestData, to: workingDirectory.appending(path: "manifest.json"))
        try checkPublishedBudget(
            observationBytes: jsonl.count,
            extraFiles: expectations.isEmpty ? 1 : 2,
            extraBytes: (expectations.isEmpty ? 0 : (files.first { $0.kind == .expectations }?.byteCount ?? 0)) + manifestData.count
        )
        try removePrivateWorkingFiles()
        try FileManager.default.moveItem(at: workingDirectory, to: publishedDirectory)
    }

    private func checkPublishedBudget(observationBytes: Int, extraFiles: Int, extraBytes: Int) throws {
        let publishedFiles = 1 + extraFiles + rawFiles.count
        guard publishedFiles <= limits.maximumRegularFiles else {
            throw CaptureFileIOError.tooManyEntries
        }
        let total = observationBytes + rawBytes + extraBytes
        guard total <= limits.maximumBundleBytes else {
            throw CaptureFileIOError.tooLarge(maximumBytes: limits.maximumBundleBytes)
        }
    }

    private func removePrivateWorkingFiles() throws {
        let journals = workingDirectory.appending(path: "observations", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: journals.path) {
            try FileManager.default.removeItem(at: journals)
        }
        for name in ["plan.json", "state.json"] {
            let url = workingDirectory.appending(path: name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func fileEntry(_ relativePath: String, kind: CaptureFileKind) throws -> CaptureFileEntry {
        let url = try CaptureFileIO.resolvedMember(root: workingDirectory, relativePath: relativePath)
        let data = try CaptureFileIO.readRegularFileNoFollow(at: url, maximumBytes: limits.maximumBundleBytes)
        return CaptureFileEntry(
            relativePath: relativePath,
            byteCount: data.count,
            sha256: CaptureDigest.sha256Hex(data),
            kind: kind
        )
    }

    private func writePlanAndState() throws {
        let data = try CaptureJSONCoding.encoder(prettyPrinted: true).encode(plan)
        try CaptureFileIO.writeAtomically(data, to: workingDirectory.appending(path: "plan.json"))
        let state = try CaptureJSONCoding.encoder(prettyPrinted: true).encode(run)
        try CaptureFileIO.writeAtomically(state, to: workingDirectory.appending(path: "state.json"))
    }

    private func validate(_ observation: CaptureObservation) throws {
        guard plan.coordinates.contains(observation.coordinate) else {
            throw CaptureBundleError.extraObservation(observation.coordinate.identity)
        }
        if observations.values.contains(where: {
            $0.coordinate == observation.coordinate && $0.observationID != observation.observationID
        }) {
            throw CaptureBundleError.multipleAttemptsUnsupported(observation.coordinate.identity)
        }
        if observation.execution != .returned, case .returned = observation.output {
            throw CaptureBundleError.captureFailed("A thrown or cancelled observation cannot include a successful output.")
        }
    }

    private static func validatePlan(_ plan: CapturePlan, limits: CaptureLimits) throws {
        guard plan.cases.count <= limits.maximumPlannedTrials else {
            throw CaptureBundleError.planTooLarge(maximum: limits.maximumPlannedTrials)
        }
        var seen: Set<String> = []
        for item in plan.cases {
            guard item.repetition >= 1 else {
                throw CaptureBundleError.invalidControlDocument("Repetition must start at 1.")
            }
            if !seen.insert(item.coordinate.identity).inserted {
                throw CaptureBundleError.duplicateCoordinate(item.coordinate.identity)
            }
        }
    }
}

public enum CaptureSessionPolicy: Sendable {
    case continueAfterCaseError
}

public actor CaptureSession<Feature: FeatureUnderTest> {
    private let feature: Feature
    private let writer: CaptureBundleWriter
    private let policy: CaptureSessionPolicy
    private var recorded: [CaptureObservation] = []

    public init(
        feature: Feature,
        writer: CaptureBundleWriter,
        policy: CaptureSessionPolicy = .continueAfterCaseError
    ) {
        self.feature = feature
        self.writer = writer
        self.policy = policy
    }

    public func run(plan: CapturePlan) async throws -> URL {
        try await writer.begin()
        var stopped = false
        for item in plan.cases {
            if Task.isCancelled {
                stopped = true
                break
            }
            let clock = ContinuousClock.now
            let observationID = UUID()
            let output: Feature.Output
            do {
                output = try await feature.evaluate(try decodeInput(item.input))
            } catch is CancellationError {
                do {
                    try await persist(CaptureObservation(
                        observationID: observationID,
                        coordinate: item.coordinate,
                        inputRevision: item.inputRevision,
                        input: item.input,
                        output: .absent,
                        execution: .cancelled,
                        durationMilliseconds: milliseconds(since: clock)
                    ))
                } catch {
                    throw CaptureBundleError.captureFailed(error.localizedDescription)
                }
                stopped = true
                break
            } catch {
                do {
                    try await persist(CaptureObservation(
                        observationID: observationID,
                        coordinate: item.coordinate,
                        inputRevision: item.inputRevision,
                        input: item.input,
                        output: .absent,
                        execution: .threw,
                        durationMilliseconds: milliseconds(since: clock),
                        error: .init(kind: "subject", message: error.localizedDescription)
                    ))
                } catch {
                    throw CaptureBundleError.captureFailed(error.localizedDescription)
                }
                if policy != .continueAfterCaseError {
                    stopped = true
                    break
                }
                continue
            }
            let encoded: CaptureOutput
            do {
                encoded = .returned(try CaptureJSON.fromEncoded(output))
            } catch {
                do {
                    try await persist(CaptureObservation(
                        observationID: observationID,
                        coordinate: item.coordinate,
                        inputRevision: item.inputRevision,
                        input: item.input,
                        output: .absent,
                        execution: .returned,
                        durationMilliseconds: milliseconds(since: clock),
                        captureError: .init(kind: "serializationFailed", message: error.localizedDescription)
                    ))
                } catch {
                    throw CaptureBundleError.captureFailed(error.localizedDescription)
                }
                continue
            }
            do {
                try await persist(CaptureObservation(
                    observationID: observationID,
                    coordinate: item.coordinate,
                    inputRevision: item.inputRevision,
                    input: item.input,
                    output: encoded,
                    execution: .returned,
                    durationMilliseconds: milliseconds(since: clock)
                ))
            } catch {
                throw CaptureBundleError.captureFailed(error.localizedDescription)
            }
        }
        if Task.isCancelled || stopped {
            return try await writer.finish(state: .cancelled)
        }
        let coverage = CaptureCoverage.reconcile(plan: plan, observations: recorded)
        return try await writer.finish(state: coverage.isComplete ? .finished : .stopped)
    }

    private func persist(_ observation: CaptureObservation) async throws {
        try await writer.record(observation)
        recorded.append(observation)
    }

    private func decodeInput(_ json: CaptureJSON) throws -> Feature.Input {
        let data = try CaptureJSONCoding.encoder().encode(json)
        return try CaptureJSONCoding.decoder().decode(Feature.Input.self, from: data)
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }
}
