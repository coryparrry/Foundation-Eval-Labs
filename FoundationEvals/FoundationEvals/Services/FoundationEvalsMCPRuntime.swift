import Foundation

@MainActor
final class FoundationEvalsMCPRuntime {
    private let store: EvaluationStore
    private var server: MCPServer?
    weak var settingsController: MCPSettingsController?

    init(store: EvaluationStore) {
        self.store = store
    }

    func start(_ configuration: CodexMCPConfiguration) async throws {
        guard server == nil else { throw MCPServerError.alreadyRunning }
        let server = MCPServer(
            port: configuration.port,
            bearerToken: configuration.bearerToken,
            authority: MCPStoreAuthority.make(store: store),
            onAuthenticatedRequest: { [weak self] date in
                await self?.settingsController?.recordConnection(at: date)
            }
        )
        try await server.start()
        self.server = server
    }

    func stop() async {
        guard let server else { return }
        self.server = nil
        await server.stop()
    }

    func prepareForTermination() async {
        store.cancelRun()
        await stop()
    }
}
