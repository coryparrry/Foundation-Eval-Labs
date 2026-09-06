import SwiftUI

struct AppSettingsView: View {
    @Bindable var mcpSettings: MCPSettingsController
    @Bindable var telemetry: TelemetryController

    var body: some View {
        TabView {
            MCPSettingsView(controller: mcpSettings)
                .tabItem { Label("MCP Connector", systemImage: "network") }

            Form {
                Section("Optional telemetry") {
                    Toggle("Share usage statistics", isOn: Binding(
                        get: { telemetry.isEnabled },
                        set: { telemetry.setEnabled($0) }
                    ))
                    .disabled(!telemetry.isConfigured)
                    .accessibilityIdentifier("Share usage statistics")

                    Text("Help improve Foundation Evals by sharing app opens, evaluation counts, run durations, and completion or failure outcomes with PostHog. Includes app and macOS versions and a random installation identifier.")
                        .foregroundStyle(.secondary)

                    Text("Off by default. Prompts, responses, suite names, reference files, provider addresses, and credentials are never included. No screen recording or automatic interaction tracking.")
                        .foregroundStyle(.secondary)

                    Text("Turning this off stops new telemetry and clears queued events. Data already received by PostHog is not deleted.")
                        .foregroundStyle(.secondary)

                    if !telemetry.isConfigured {
                        Text("Telemetry is unavailable in this build.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 620, height: 440)
            .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .padding(12)
    }
}
