import Foundation

public struct CaptureBundle: Sendable, Equatable {
    public var root: URL
    public var manifest: CaptureManifest
    public var observations: [CaptureObservation]
    public var expectations: [CaptureExpectation]
    public var coverage: CaptureCoverage
    public var eligibility: CaptureImportEligibility
    public var warnings: [String]
    public var manifestDigest: String

    public init(
        root: URL,
        manifest: CaptureManifest,
        observations: [CaptureObservation],
        expectations: [CaptureExpectation],
        coverage: CaptureCoverage,
        eligibility: CaptureImportEligibility,
        warnings: [String],
        manifestDigest: String
    ) {
        self.root = root
        self.manifest = manifest
        self.observations = observations
        self.expectations = expectations
        self.coverage = coverage
        self.eligibility = eligibility
        self.warnings = warnings
        self.manifestDigest = manifestDigest
    }
}

public enum CaptureBundleValidator {
    public static func load(
        root: URL,
        limits: CaptureLimits = .version1,
        stagedBytes: [String: Data]? = nil
    ) throws -> CaptureBundle {
        let manifestData = try read(root: root, relativePath: "manifest.json", maximumBytes: limits.maximumManifestBytes, stagedBytes: stagedBytes)
        try JSONStructure.validate(
            manifestData,
            maximumDepth: limits.maximumJSONNestingDepth,
            rejectDuplicateKeys: true
        )
        let manifest = try CaptureJSONCoding.decoder().decode(CaptureManifest.self, from: manifestData)
        guard manifest.format == CaptureFormat.name else {
            throw CaptureBundleError.unsupportedFormat(manifest.format)
        }
        guard manifest.formatVersion == CaptureFormat.version else {
            throw CaptureBundleError.unsupportedVersion(manifest.formatVersion)
        }

        var warnings: [String] = []
        guard manifest.plan.cases.count <= limits.maximumPlannedTrials else {
            throw CaptureBundleError.planTooLarge(maximum: limits.maximumPlannedTrials)
        }
        let observationsEntry = try requiredFile(manifest.files, path: "observations.jsonl", kind: .observations)
        try validateFileEntries(manifest.files, root: root, limits: limits, stagedBytes: stagedBytes)
        let observations = try loadObservations(
            root: root,
            relativePath: observationsEntry.relativePath,
            limits: limits,
            stagedBytes: stagedBytes
        )
        try validateIdentities(plan: manifest.plan, observations: observations)
        try validatePlanAgreement(plan: manifest.plan, observations: observations)
        let coverage = CaptureCoverage.reconcile(plan: manifest.plan, observations: observations)
        if !coverage.extraCoordinates.isEmpty {
            throw CaptureBundleError.extraObservation(coverage.extraCoordinates[0].identity)
        }

        let expectations: [CaptureExpectation]
        if let expectationsEntry = manifest.files.first(where: { $0.kind == .expectations }) {
            let data = try read(
                root: root,
                relativePath: expectationsEntry.relativePath,
                maximumBytes: limits.maximumManifestBytes,
                stagedBytes: stagedBytes
            )
            expectations = try CaptureJSONCoding.decoder().decode([CaptureExpectation].self, from: data)
        } else {
            expectations = []
        }
        if !coverage.isComplete {
            warnings.append("Incomplete capture · Some planned cases were not recorded")
        }
        return CaptureBundle(
            root: root,
            manifest: manifest,
            observations: observations,
            expectations: expectations,
            coverage: coverage,
            eligibility: .inspectionOnly,
            warnings: Array(Set(warnings)).sorted(),
            manifestDigest: CaptureDigest.sha256Hex(manifestData)
        )
    }

    private static func loadObservations(
        root: URL,
        relativePath: String,
        limits: CaptureLimits,
        stagedBytes: [String: Data]?
    ) throws -> [CaptureObservation] {
        let data = try read(root: root, relativePath: relativePath, maximumBytes: limits.maximumBundleBytes, stagedBytes: stagedBytes)
        if data.isEmpty { return [] }
        var observations: [CaptureObservation] = []
        var lineNumber = 0
        var start = data.startIndex
        while start < data.endIndex {
            lineNumber += 1
            let end = data[start...].firstIndex(of: UInt8(ascii: "\n")) ?? data.endIndex
            let line = data[start..<end]
            start = end == data.endIndex ? data.endIndex : data.index(after: end)
            if line.isEmpty { continue }
            guard line.count <= limits.maximumObservationLineBytes else {
                throw CaptureFileIOError.tooLarge(maximumBytes: limits.maximumObservationLineBytes)
            }
            try JSONStructure.validate(
                Data(line),
                maximumDepth: limits.maximumJSONNestingDepth,
                rejectDuplicateKeys: true
            )
            observations.append(try CaptureJSONCoding.decoder().decode(CaptureObservation.self, from: Data(line)))
        }
        return observations
    }

    private static func validateIdentities(plan: CapturePlan, observations: [CaptureObservation]) throws {
        var planned: Set<String> = []
        for item in plan.cases {
            if !planned.insert(item.coordinate.identity).inserted {
                throw CaptureBundleError.duplicateCoordinate(item.coordinate.identity)
            }
        }
        var seenCoordinates: Set<String> = []
        var seenObservationIDs: Set<UUID> = []
        var seenAttempts: [String: UUID] = [:]
        for observation in observations {
            if !seenObservationIDs.insert(observation.observationID).inserted {
                throw CaptureBundleError.duplicateObservation(observation.observationID.uuidString)
            }
            guard observation.coordinate.repetition >= 1 else {
                throw CaptureBundleError.invalidControlDocument("Repetition must start at 1.")
            }
            let identity = observation.coordinate.identity
            if !seenCoordinates.insert(identity).inserted {
                throw CaptureBundleError.multipleAttemptsUnsupported(identity)
            }
            if let existing = seenAttempts[identity], existing != observation.attemptID {
                throw CaptureBundleError.multipleAttemptsUnsupported(identity)
            }
            seenAttempts[identity] = observation.attemptID
            if !planned.contains(identity) {
                throw CaptureBundleError.extraObservation(identity)
            }
        }
    }

    private static func validatePlanAgreement(plan: CapturePlan, observations: [CaptureObservation]) throws {
        let planned = Dictionary(uniqueKeysWithValues: plan.cases.map { ($0.coordinate.identity, $0) })
        for observation in observations {
            guard let item = planned[observation.coordinate.identity] else {
                throw CaptureBundleError.extraObservation(observation.coordinate.identity)
            }
            guard item.inputRevision == observation.inputRevision, item.input == observation.input else {
                throw CaptureBundleError.observationPlanMismatch(observation.coordinate.identity)
            }
        }
    }

    private static func requiredFile(_ files: [CaptureFileEntry], path: String, kind: CaptureFileKind) throws -> CaptureFileEntry {
        guard let entry = files.first(where: { $0.relativePath == path && $0.kind == kind }) else {
            throw CaptureBundleError.missingRequiredFile(path)
        }
        return entry
    }

    private static func validateFileEntries(
        _ files: [CaptureFileEntry],
        root: URL,
        limits: CaptureLimits,
        stagedBytes: [String: Data]?
    ) throws {
        var seen: Set<String> = []
        for entry in files {
            if !seen.insert(entry.relativePath).inserted {
                throw CaptureBundleError.conflictingFiles
            }
            let data = try read(root: root, relativePath: entry.relativePath, maximumBytes: limits.maximumBundleBytes, stagedBytes: stagedBytes)
            guard data.count == entry.byteCount, CaptureDigest.sha256Hex(data) == entry.sha256 else {
                throw CaptureBundleError.invalidControlDocument("File \(entry.relativePath) does not match its digest.")
            }
        }
    }

    private static func read(
        root: URL,
        relativePath: String,
        maximumBytes: Int,
        stagedBytes: [String: Data]?
    ) throws -> Data {
        if let staged = stagedBytes?[relativePath] {
            guard staged.count <= maximumBytes else {
                throw CaptureFileIOError.tooLarge(maximumBytes: maximumBytes)
            }
            return staged
        }
        let url = try CaptureFileIO.resolvedMember(root: root, relativePath: relativePath)
        return try CaptureFileIO.readRegularFileNoFollow(at: url, maximumBytes: maximumBytes)
    }
}
