import SwiftUI
import UniformTypeIdentifiers

struct AppleTestConnectionView: View {
    @Bindable var coordinator: ScenarioCoordinator
    @State private var showingProjectImporter = false
    @State private var showingBuildApproval = false

    @State private var page: IntentConnectionPage = .connection

    var body: some View {
        IntentLabEditorLayout(heading: "INTENT SETUP", selection: $page) {
            switch page {
            case .connection: connectionCard
            case .advanced: advancedConfiguration
            case .harness: harnessGuidance
            }
        }
        .fileImporter(
            isPresented: $showingProjectImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            do {
                let url = try result.get().first
                guard let url else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                coordinator.selectContainer(url)
            } catch {
                coordinator.notice = error.localizedDescription
            }
        }
        .fileDialogMessage("Choose the app's Xcode project or workspace.")
        .fileDialogConfirmationLabel("Choose Project")
        .confirmationDialog(
            "Allow Xcode to build this project?",
            isPresented: $showingBuildApproval
        ) {
            Button("Approve and Inspect") {
                Task { await coordinator.approveBuildAndDiscover() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Xcode builds can execute project scripts and resolve package dependencies. Approval lasts for this app session and is not restored after relaunch.")
        }
        .onChange(of: coordinator.configuration.destinationIdentifier) { _, identifier in
            Task { await coordinator.selectDevice(identifier) }
        }
    }

    private var connectionCard: some View {
        IntentLabCard(
            "Connect an iPhone",
            subtitle: "Choose the app project and a paired iPhone. Intent Lab discovers the Xcode details for you."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                connectionField(
                    title: "Choose Xcode project",
                    detail: selectedProjectName ?? "Select the app's .xcodeproj or .xcworkspace."
                ) {
                    Button(selectedProjectName == nil ? "Choose Project…" : "Change…", systemImage: "folder") {
                        showingProjectImporter = true
                    }
                    .disabled(coordinator.isDiscoveringConnection)
                }

                connectionField(
                    title: "Choose connected iPhone",
                    detail: selectedDeviceDetail
                ) {
                    HStack(spacing: 8) {
                        Picker("Connected iPhone", selection: $coordinator.configuration.destinationIdentifier) {
                            Text("Choose iPhone").tag("")
                            ForEach(coordinator.discoveredDevices) { device in
                                Text(device.available ? device.name : "\(device.name) — unavailable")
                                    .tag(device.identifier)
                                    .disabled(!device.available)
                            }
                        }
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await coordinator.refreshDevices() }
                        }
                        .labelStyle(.iconOnly)
                        .help("Refresh connected iPhones")
                    }
                }

                connectionField(
                    title: "Approve Build and Run",
                    detail: approvalDetail
                ) {
                    Button(
                        coordinator.isDiscoveringConnection ? "Inspecting…" : "Approve Build and Run",
                        systemImage: "checkmark.shield"
                    ) {
                        showingBuildApproval = true
                    }
                    .disabled(selectedProjectName == nil || coordinator.isDiscoveringConnection)
                }

                connectionField(
                    title: "Run",
                    detail: "When the connection is ready, use Run scenario in the toolbar."
                ) {
                    Image(systemName: coordinator.preflight?.isReady == true ? "play.circle.fill" : "play.circle")
                        .font(.title2)
                        .foregroundStyle(coordinator.preflight?.isReady == true ? Color.accentColor : .secondary)
                        .accessibilityLabel(coordinator.preflight?.isReady == true ? "Ready to run" : "Complete setup before running")
                }

                if let discovery = coordinator.connectionDiscovery {
                    discoveredChoices(discovery)
                }

                connectionStatus

                recoveryControls
            }
        }
    }

    private var advancedConfiguration: some View {
        EditorSection(
            "Advanced configuration",
            systemImage: "slider.horizontal.3",
            description: "Xcode scheme, test target and device settings"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                advancedRow("Container") {
                    Text(coordinator.configuration.containerPath.isEmpty ? "Choose a project above" : coordinator.configuration.containerPath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                advancedRow("Scheme") {
                    TextField("App scheme", text: $coordinator.configuration.scheme)
                }
                advancedRow("UI-test target") {
                    TextField("AppUITests", text: $coordinator.configuration.testTarget)
                }
                advancedRow("Test bundle ID") {
                    TextField("com.example.AppUITests", text: $coordinator.configuration.testBundleIdentifier)
                }
                advancedRow("Device identifier") {
                    TextField("000081…", text: $coordinator.configuration.destinationIdentifier)
                }
                DisclosureGroup("Command preview") {
                    Text(commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func connectionField<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.semibold))
            content().controlSize(.regular)
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func discoveredChoices(_ discovery: XcodeConnectionDiscovery) -> some View {
        if discovery.schemes.count > 1 || discovery.applications.count > 1 || discovery.uiTestBundles.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Label("Choose the matching app configuration", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.callout.weight(.semibold))
                if discovery.schemes.count > 1 {
                    Picker("Scheme", selection: Binding(
                        get: { coordinator.configuration.scheme },
                        set: { coordinator.selectScheme($0) }
                    )) {
                        Text("Choose scheme").tag("")
                        ForEach(discovery.schemes, id: \.self) { Text($0).tag($0) }
                    }
                }
                if discovery.applications.count > 1 {
                    Picker("Application", selection: Binding(
                        get: { coordinator.draft.target.bundleIdentifier },
                        set: { bundleIdentifier in
                            guard let product = discovery.applications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
                            coordinator.selectApplication(product)
                        }
                    )) {
                        Text("Choose application").tag("")
                        ForEach(discovery.applications) { Text($0.targetName).tag($0.bundleIdentifier) }
                    }
                }
                if discovery.uiTestBundles.count > 1 {
                    Picker("UI-test target", selection: $coordinator.configuration.testTarget) {
                        Text("Choose UI-test target").tag("")
                        ForEach(discovery.uiTestBundles) { Text($0.targetName).tag($0.targetName) }
                    }
                    .onChange(of: coordinator.configuration.testTarget) { _, targetName in
                        guard let product = discovery.uiTestBundles.first(where: { $0.targetName == targetName }) else { return }
                        coordinator.selectUITestBundle(product)
                    }
                }
                Button("Check connection", systemImage: "checklist") {
                    Task { await coordinator.refreshPreflight() }
                }
            }
            .padding(14)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private var connectionStatus: some View {
        if let report = coordinator.preflight {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    report.isReady ? "Ready to run on \(selectedDeviceName ?? "iPhone")" : "Connection needs attention",
                    systemImage: report.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(report.isReady ? .green : .orange)
                .font(.callout.weight(.semibold))
                if !report.isReady {
                    ForEach(report.checks.filter { $0.state != .ready }) { check in
                        Text("• \(check.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((report.isReady ? Color.green : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var harnessGuidance: some View {
        EditorSection(
            "Harness requirements",
            systemImage: "checkmark.shield",
            description: "Required test support and observable results"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("The selected UI-test target must include IntentLabScenarioTests/testIntentLabScenario and harness version \(ScenarioInvocationIdentity.currentHarnessVersion).")
                Text("The fixture must expose reset, invocation-correlation, and observable-result accessibility values. Intent Lab reports missing signing, test identity, fixture, and evidence separately; it never changes signing automatically.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }

    @ViewBuilder private var recoveryControls: some View {
        if !coordinator.recoveryJournals.isEmpty {
            Divider()
            Label("Device recovery required", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Automatic clearing is intentionally disabled until the device proves that this invocation stopped and the fixture reset. You can clear it after verifying both conditions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("I verified termination and fixture readiness") {
                Task { await coordinator.clearDeviceQuarantine(fixtureReadinessProven: true) }
            }
        }
    }

    private func advancedRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.callout).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            content().frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedProjectName: String? {
        guard !coordinator.configuration.containerPath.isEmpty else { return nil }
        return URL(filePath: coordinator.configuration.containerPath).lastPathComponent
    }

    private var selectedDeviceName: String? {
        coordinator.discoveredDevices.first { $0.identifier == coordinator.configuration.destinationIdentifier }?.name
    }

    private var selectedDeviceDetail: String {
        guard !coordinator.configuration.destinationIdentifier.isEmpty else { return "Select an available paired physical iPhone." }
        return selectedDeviceName ?? "The saved iPhone is not currently available."
    }

    private var approvalDetail: String {
        if coordinator.projectTrusted { return "Approved for this app session; discovered settings are shown below." }
        return "Required because Xcode builds can execute project scripts."
    }

    private var commandPreview: String {
        let kind = coordinator.configuration.isWorkspace ? "-workspace" : "-project"
        return "xcodebuild \(kind) \"\(coordinator.configuration.containerPath)\" -scheme \"\(coordinator.configuration.scheme)\" -destination \"id=\(coordinator.configuration.destinationIdentifier)\" build-for-testing"
    }
}

private enum IntentConnectionPage: String, IntentLabEditorPage {
    case connection, advanced, harness
    var id: Self { self }
    var title: String {
        switch self { case .connection: "Connection"; case .advanced: "Advanced"; case .harness: "Test support" }
    }
    var subtitle: String {
        switch self {
        case .connection: "App project & connected iPhone"
        case .advanced: "Xcode & device configuration"
        case .harness: "Required test support & evidence"
        }
    }
    var symbol: String {
        switch self { case .connection: "iphone"; case .advanced: "slider.horizontal.3"; case .harness: "checkmark.shield" }
    }
}
