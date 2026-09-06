import Foundation

/// Deliberately contains no free-form evaluation content or identifiers.
enum TelemetryEvent {
    enum Outcome: String { case completed, cancelled, failed }
    case appOpened
    case evaluationStarted(caseCount: Int, sampleCount: Int)
    case evaluationFinished(outcome: Outcome, sampleCount: Int, durationSeconds: Double)

    var name: String {
        switch self {
        case .appOpened: "foundation_evals_app_opened"
        case .evaluationStarted: "foundation_evals_evaluation_started"
        case .evaluationFinished: "foundation_evals_evaluation_finished"
        }
    }

    var properties: [String: Any] {
        switch self {
        case .appOpened: [:]
        case let .evaluationStarted(caseCount, sampleCount):
            ["case_count": max(0, caseCount), "sample_count": max(0, sampleCount)]
        case let .evaluationFinished(outcome, sampleCount, durationSeconds):
            ["outcome": outcome.rawValue, "sample_count": max(0, sampleCount),
             "duration_seconds": durationSeconds.isFinite ? max(0, durationSeconds.rounded()) : 0.0]
        }
    }

    /// Also strips SDK enrichment (device, location, screen and session properties).
    nonisolated static func allowedProperties(for name: String) -> Set<String>? {
        let common: Set<String> = ["app_version", "os_major", "$process_person_profile", "$geoip_disable"]
        switch name {
        case "foundation_evals_app_opened": return common
        case "foundation_evals_evaluation_started": return common.union(["case_count", "sample_count"])
        case "foundation_evals_evaluation_finished": return common.union(["outcome", "sample_count", "duration_seconds"])
        default: return nil
        }
    }
}
