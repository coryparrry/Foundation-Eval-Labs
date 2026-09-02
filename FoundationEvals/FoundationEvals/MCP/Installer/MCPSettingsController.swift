import AppKit
import Foundation
import Observation

struct MCPServerControl: Sendable {
    let start: @MainActor @Sendable (CodexMCPConfiguration) async throws -> Void
    let stop: @MainActor @Sendable () async throws -> Void

    init(
        start: @escaping @MainActor @Sendable (CodexMCPConfiguration) async throws -> Void,
        stop: @escaping @MainActor @Sendable () async throws -> Void
    ) {
        self.start = start
        self.stop = stop
    }

    static let disconnected = MCPServerControl(start: { _ in }, stop: {})
}

enum MCPConnectorServerState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Running"
        case .stopping: "Stopping…"
        case .failed: "Needs attention"
        }
    }
}

enum CodexMCPInstallationState: Equatable, Sendable {
    case notConfigured
    case installed
    case needsAttention

    var label: String {
        switch self {
        case .notConfigured: "Not installed"
        case .installed: "Installed"
        case .needsAttention: "Needs attention"
        }
    }
}

private enum MCPSettingsError: Error, LocalizedError {
    case noConfigurationDirectory
    case configurationPermissionUnavailable
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .noConfigurationDirectory:
            "Choose the Codex configuration directory."
        case .configurationPermissionUnavailable:
            "Access to the Codex configuration folder is no longer available. Choose the folder again."
        case .rollbackFailed:
            "The previous MCP configuration could not be restored completely. Review the Codex backup before retrying."
        }
    }
}

@MainActor
@Observable
final class MCPSettingsController {
    private static let legacyPortKey = "mcp.server.port"
    private static let bookmarkKey = "mcp.codex.configuration-directory-bookmark"

    private let serverControl: MCPServerControl
    private let installer: CodexMCPInstaller
    private let tokenStore: MCPBearerTokenStore
    private let userDefaults: UserDefaults
    private var bearerToken: String?
    private var needsFixedPortMigration: Bool

    private(set) var serverState: MCPConnectorServerState = .stopped
    private(set) var installationState: CodexMCPInstallationState = .notConfigured
    private(set) var lastConnection: Date?
    private(set) var isBusy = false
    var notice: String?

    init(
        serverControl: MCPServerControl,
        userDefaults: UserDefaults = .standard,
        installer: CodexMCPInstaller = CodexMCPInstaller(),
        tokenStore: MCPBearerTokenStore = MCPBearerTokenStore()
    ) {
        self.serverControl = serverControl
        self.userDefaults = userDefaults
        self.installer = installer
        self.tokenStore = tokenStore
        let legacyPort = userDefaults.integer(forKey: Self.legacyPortKey)
        needsFixedPortMigration = (1_024...65_535).contains(legacyPort)
            && legacyPort != CodexMCPConfiguration.defaultPort
        if !needsFixedPortMigration {
            userDefaults.removeObject(forKey: Self.legacyPortKey)
        }
        refreshInstallationState()
    }

    var endpoint: URL {
        URL(string: "http://127.0.0.1:\(CodexMCPConfiguration.defaultPort)/mcp")!
    }

    var hasStoredCodexDirectory: Bool {
        userDefaults.data(forKey: Self.bookmarkKey) != nil
    }

    func startServer() async {
        guard !isBusy, serverState != .running else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let configuration = try await currentConfiguration()
            try await startServer(using: configuration)
            notice = nil
        } catch {
            notice = safeDescription(for: error)
        }
    }

    func rotateToken() async {
        guard !isBusy else { return }
        do {
            let token = try tokenStore.generate()
            try await reconfigure(token: token)
            notice = serverState == .running
                ? "The MCP credential was rotated. Restart Codex to reconnect."
                : "The MCP credential was rotated. Use the Codex connection button, then restart Codex."
        } catch {
            notice = safeDescription(for: error)
        }
    }

    func installOrUpdateCodex() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            if !hasStoredCodexDirectory {
                guard chooseCodexConfigurationDirectory() else { return }
            }
            let configuration = try await currentConfiguration()
            let receipt = try withCodexDirectory { directory in
                try installer.installOrUpdate(in: directory, configuration: configuration)
            }
            needsFixedPortMigration = false
            userDefaults.removeObject(forKey: Self.legacyPortKey)
            installationState = .installed
            let successNotice: String? = switch receipt.change {
            case .installed: "Foundation Evals is ready. Restart Codex to connect."
            case .updated: "The Codex connection was updated. Restart Codex to reconnect."
            case .unchanged: "Foundation Evals is ready. Restart Codex if it does not appear."
            case .removed: nil
            }
            do {
                try await startServer(using: configuration)
                notice = successNotice
            } catch {
                notice = "Codex was configured, but the local connector could not start. " + safeDescription(for: error)
            }
        } catch {
            installationState = .needsAttention
            notice = safeDescription(for: error) + " You can copy the manual configuration instead."
        }
    }

    func removeFromCodex() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard hasStoredCodexDirectory else {
                installationState = .notConfigured
                return
            }
            let receipt = try withCodexDirectory { directory in
                try installer.remove(from: directory)
            }
            needsFixedPortMigration = false
            userDefaults.removeObject(forKey: Self.legacyPortKey)
            installationState = .notConfigured
            notice = receipt.change == .removed
                ? "Foundation Evals was removed from Codex. Restart Codex to apply the change."
                : "No managed Foundation Evals entry was present."
        } catch {
            installationState = .needsAttention
            notice = safeDescription(for: error)
        }
    }

    func chooseDifferentCodexFolder() {
        guard !isBusy else { return }
        if chooseCodexConfigurationDirectory() {
            refreshInstallationState()
            notice = "The Codex configuration folder was updated."
        }
    }

    func copyEndpoint() {
        copyToPasteboard(endpoint.absoluteString)
        notice = "MCP endpoint copied."
    }

    func copyManualConfiguration() async {
        do {
            copyToPasteboard(try await currentConfiguration().manualSnippet)
            notice = "Codex configuration copied. Treat it like a password because it contains the MCP credential."
        } catch {
            notice = safeDescription(for: error)
        }
    }

    func recordConnection(at date: Date = .now) {
        lastConnection = date
    }

    func refreshInstallationState() {
        guard hasStoredCodexDirectory else {
            installationState = .notConfigured
            return
        }
        do {
            let detectedState: CodexMCPInstallationState = try withCodexDirectory { directory in
                try installer.isInstalled(in: directory) ? .installed : .notConfigured
            }
            installationState = needsFixedPortMigration && detectedState == .installed
                ? .needsAttention
                : detectedState
        } catch {
            installationState = .needsAttention
        }
    }

    private func reconfigure(token newToken: String) async throws {
        isBusy = true
        let oldToken = try await loadToken()
        let oldConfiguration = try CodexMCPConfiguration(bearerToken: oldToken)
        let newConfiguration = try CodexMCPConfiguration(bearerToken: newToken)
        let wasRunning = serverState == .running
        var updatedCodex = false
        defer { isBusy = false }

        if wasRunning {
            serverState = .stopping
            do {
                try await serverControl.stop()
                serverState = .stopped
            } catch {
                serverState = .failed
                throw error
            }
        }

        do {
            try await tokenStore.save(newToken)
            bearerToken = newToken

            if installationState == .installed, hasStoredCodexDirectory {
                _ = try withCodexDirectory { directory in
                    try installer.installOrUpdate(in: directory, configuration: newConfiguration)
                }
                updatedCodex = true
            }

            if wasRunning {
                serverState = .starting
                try await serverControl.start(newConfiguration)
                serverState = .running
            } else {
                serverState = .stopped
            }
        } catch {
            var rollbackFailed = false
            do {
                try await tokenStore.save(oldToken)
            } catch {
                rollbackFailed = true
            }
            bearerToken = oldToken
            if updatedCodex {
                do {
                    _ = try withCodexDirectory { directory in
                        try installer.installOrUpdate(in: directory, configuration: oldConfiguration)
                    }
                } catch {
                    rollbackFailed = true
                }
            }
            if wasRunning {
                do {
                    try await serverControl.start(oldConfiguration)
                    serverState = .running
                } catch {
                    serverState = .failed
                    rollbackFailed = true
                }
            } else {
                serverState = .stopped
            }
            if rollbackFailed {
                serverState = .failed
                throw MCPSettingsError.rollbackFailed
            }
            throw error
        }
    }

    private func currentConfiguration() async throws -> CodexMCPConfiguration {
        try await CodexMCPConfiguration(
            port: CodexMCPConfiguration.defaultPort,
            bearerToken: loadToken()
        )
    }

    private func startServer(using configuration: CodexMCPConfiguration) async throws {
        guard serverState != .running else { return }
        serverState = .starting
        do {
            try await serverControl.start(configuration)
            serverState = .running
        } catch {
            serverState = .failed
            throw error
        }
    }

    private func loadToken() async throws -> String {
        if let bearerToken { return bearerToken }
        let token = try await tokenStore.loadOrCreate()
        bearerToken = token
        return token
    }

    private func chooseCodexConfigurationDirectory() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex Configuration Folder"
        panel.message = "Foundation Evals will manage only its marked block in config.toml."
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        let suggested = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: suggested.path) {
            panel.directoryURL = suggested
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        guard panel.runModal() == .OK, let directory = panel.url else { return false }
        do {
            let bookmark = try directory.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            userDefaults.set(bookmark, forKey: Self.bookmarkKey)
            return true
        } catch {
            notice = "The Codex folder permission could not be saved."
            return false
        }
    }

    private func withCodexDirectory<T>(_ action: (URL) throws -> T) throws -> T {
        guard let bookmark = userDefaults.data(forKey: Self.bookmarkKey) else {
            throw MCPSettingsError.noConfigurationDirectory
        }
        var isStale = false
        let directory = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let didStart = directory.startAccessingSecurityScopedResource()
        guard didStart else { throw MCPSettingsError.configurationPermissionUnavailable }
        defer { directory.stopAccessingSecurityScopedResource() }
        if isStale {
            let refreshed = try directory.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            userDefaults.set(refreshed, forKey: Self.bookmarkKey)
        }
        return try action(directory)
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func safeDescription(for error: Error) -> String {
        switch error {
        case let error as CodexMCPInstallerError:
            error.localizedDescription
        case let error as MCPBearerTokenStoreError:
            error.localizedDescription
        case let error as MCPSettingsError:
            error.localizedDescription
        case let error as MCPServerError:
            error.localizedDescription
        default:
            "The MCP configuration could not be changed safely."
        }
    }
}
