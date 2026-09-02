import SwiftUI

struct MCPSettingsView: View {
    @Bindable var controller: MCPSettingsController
    @State private var portText: String
    @State private var isConfirmingRemoval = false
    @State private var isConfirmingRotation = false

    init(controller: MCPSettingsController) {
        self.controller = controller
        _portText = State(initialValue: String(controller.port))
    }

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Status") {
                    Label(controller.serverState.label, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                }

                LabeledContent("Endpoint") {
                    HStack(spacing: 8) {
                        Text(controller.endpoint.absoluteString)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Copy", systemImage: "doc.on.doc") {
                            controller.copyEndpoint()
                        }
                        .labelStyle(.iconOnly)
                        .help("Copy endpoint")
                    }
                }

                LabeledContent("Port") {
                    HStack(spacing: 8) {
                        TextField("Port", text: $portText)
                            .frame(width: 84)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(applyPort)
                        Button(controller.serverState == .running ? "Apply and Restart" : "Apply") {
                            applyPort()
                        }
                        .disabled(controller.isBusy || parsedPort == nil || parsedPort == controller.port)
                    }
                }

                if let lastConnection = controller.lastConnection {
                    LabeledContent("Last connection") {
                        Text(lastConnection, format: .dateTime.month().day().hour().minute().second())
                    }
                }

                HStack {
                    if controller.serverState == .running {
                        Button("Stop Server") {
                            Task { await controller.stopServer() }
                        }
                    } else {
                        Button("Start Server") {
                            Task { await controller.startServer() }
                        }
                    }
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .opacity(controller.isBusy ? 1 : 0)
                        .accessibilityHidden(!controller.isBusy)
                }
            }

            Section("Codex") {
                LabeledContent("Configuration") {
                    Text(controller.installationState.label)
                        .foregroundStyle(controller.installationState == .needsAttention ? .orange : .secondary)
                }

                Text("Installation updates only the marked Foundation Evals block in Codex config.toml. The first install asks you to choose the Codex configuration folder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(controller.installationState == .installed ? "Update Codex" : "Install in Codex") {
                        Task { await controller.installOrUpdateCodex() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Copy Manual Configuration") {
                        Task { await controller.copyManualConfiguration() }
                    }

                    Button("Change Folder…") {
                        controller.chooseDifferentCodexFolder()
                    }

                    Spacer()

                    Button("Remove from Codex", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                    .disabled(controller.installationState == .notConfigured)
                }
                .disabled(controller.isBusy)
            }

            Section("Credential") {
                Text("A local bearer credential protects the loopback server. Codex stores a copy in its configuration, so treat copied configuration as a password.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Rotate Credential…") {
                    isConfirmingRotation = true
                }
                .disabled(controller.isBusy)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 540)
        .navigationTitle("MCP Connector")
        .onChange(of: controller.port) { _, newPort in
            portText = String(newPort)
        }
        .confirmationDialog(
            "Remove Foundation Evals from Codex?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove from Codex", role: .destructive) {
                Task { await controller.removeFromCodex() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only the managed Foundation Evals block is removed. Restart Codex afterward.")
        }
        .confirmationDialog(
            "Rotate the MCP credential?",
            isPresented: $isConfirmingRotation,
            titleVisibility: .visible
        ) {
            Button("Rotate Credential", role: .destructive) {
                Task { await controller.rotateToken() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The server and managed Codex configuration will be updated together. Restart Codex afterward.")
        }
        .alert(
            "MCP Connector",
            isPresented: Binding(
                get: { controller.notice != nil },
                set: { if !$0 { controller.notice = nil } }
            )
        ) {
            Button("OK") { controller.notice = nil }
        } message: {
            Text(controller.notice ?? "")
        }
    }

    private var parsedPort: Int? {
        guard let port = Int(portText), (1_024...65_535).contains(port) else { return nil }
        return port
    }

    private var statusSymbol: String {
        switch controller.serverState {
        case .running: "checkmark.circle.fill"
        case .starting, .stopping: "circle.dotted"
        case .stopped: "circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch controller.serverState {
        case .running: .green
        case .starting, .stopping: .secondary
        case .stopped: .secondary
        case .failed: .orange
        }
    }

    private func applyPort() {
        guard let parsedPort else { return }
        Task { await controller.applyPort(parsedPort) }
    }
}

#Preview {
    MCPSettingsView(controller: MCPSettingsController(serverControl: .disconnected))
}
