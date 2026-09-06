import Foundation

/// App usage only. Evaluation activity and content have no telemetry representation.
enum TelemetryEvent {
    case appOpened

    var name: String { "foundation_evals_app_opened" }

    /// Strips SDK enrichment and rejects all events outside this allowlist.
    nonisolated static func allowedProperties(for name: String) -> Set<String>? {
        guard name == "foundation_evals_app_opened" else { return nil }
        return ["app_version", "os_major", "$process_person_profile", "$geoip_disable"]
    }
}
