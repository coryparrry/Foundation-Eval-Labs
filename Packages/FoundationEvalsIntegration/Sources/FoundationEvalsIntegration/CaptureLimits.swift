import Foundation

/// First-version capture and import budgets. MiB is 1,048,576 bytes.
public struct CaptureLimits: Sendable, Equatable, Codable {
    public static let version1 = CaptureLimits()
    public static let mebibyte = 1_048_576

    public var maximumPlannedTrials: Int
    public var maximumConcurrentTrials: Int
    public var automaticRetries: Int
    public var maximumManifestBytes: Int
    public var maximumAppleJSONBytes: Int
    public var maximumObservationLineBytes: Int
    public var maximumBundleBytes: Int
    public var maximumRegularFiles: Int
    public var maximumVisitedEntries: Int
    public var maximumDirectoryDepth: Int
    public var maximumJSONNestingDepth: Int
    public var maximumLauncherLogBytes: Int
    public var defaultRunDeadlineSeconds: Int
    public var maximumRunDeadlineSeconds: Int

    public init(
        maximumPlannedTrials: Int = 100,
        maximumConcurrentTrials: Int = 1,
        automaticRetries: Int = 0,
        maximumManifestBytes: Int = CaptureLimits.mebibyte,
        maximumAppleJSONBytes: Int = 5 * CaptureLimits.mebibyte,
        maximumObservationLineBytes: Int = CaptureLimits.mebibyte,
        maximumBundleBytes: Int = 25 * CaptureLimits.mebibyte,
        maximumRegularFiles: Int = 256,
        maximumVisitedEntries: Int = 256,
        maximumDirectoryDepth: Int = 32,
        maximumJSONNestingDepth: Int = 64,
        maximumLauncherLogBytes: Int = CaptureLimits.mebibyte,
        defaultRunDeadlineSeconds: Int = 600,
        maximumRunDeadlineSeconds: Int = 1_800
    ) {
        self.maximumPlannedTrials = maximumPlannedTrials
        self.maximumConcurrentTrials = maximumConcurrentTrials
        self.automaticRetries = automaticRetries
        self.maximumManifestBytes = maximumManifestBytes
        self.maximumAppleJSONBytes = maximumAppleJSONBytes
        self.maximumObservationLineBytes = maximumObservationLineBytes
        self.maximumBundleBytes = maximumBundleBytes
        self.maximumRegularFiles = maximumRegularFiles
        self.maximumVisitedEntries = maximumVisitedEntries
        self.maximumDirectoryDepth = maximumDirectoryDepth
        self.maximumJSONNestingDepth = maximumJSONNestingDepth
        self.maximumLauncherLogBytes = maximumLauncherLogBytes
        self.defaultRunDeadlineSeconds = defaultRunDeadlineSeconds
        self.maximumRunDeadlineSeconds = maximumRunDeadlineSeconds
    }
}
