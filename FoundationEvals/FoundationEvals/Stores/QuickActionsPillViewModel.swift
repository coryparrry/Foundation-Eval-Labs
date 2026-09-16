import Foundation

typealias QuickActionsRewriteStreamProvider = @Sendable (
    QuickActionsPillRequest,
    String
) -> AsyncThrowingStream<String, Error>

/// Owns one prompt-revision session. The pill never knows about cases or prompts.
@MainActor
@Observable
final class QuickActionsPillViewModel {
    private(set) var originalSnapshot = ""
    private(set) var previewText: String?
    private(set) var phase: QuickActionsPillPhase = .idle
    private(set) var request: QuickActionsPillRequest?
    private(set) var errorMessage: String?
    var prompt = ""
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let generate: QuickActionsRewriteStreamProvider

    struct Request: Equatable {
        let id: String
        let prompt: String?
        let busyLabel: String
    }

    init(
        generate: @escaping QuickActionsRewriteStreamProvider = QuickActionsRewriteService.stream
    ) {
        self.generate = generate
    }

    var isBusy: Bool {
        switch phase {
        case .idle, .result: false
        case .thinking, .streaming: true
        }
    }

    func select(_ action: QuickActionsPillAction, source: String) {
        guard action.isEnabled, phase == .idle else { return }
        begin(.init(id: action.id, prompt: nil, busyLabel: action.busyLabel), source: source)
    }

    func submit(source: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase == .idle else { return }
        begin(.init(id: "prompt", prompt: trimmed, busyLabel: "Editing"), source: source)
    }

    func retry() {
        guard phase == .result, let request else { return }
        begin(request, source: originalSnapshot)
    }

    /// Returns the revision for the host to commit, then ends the session.
    func keep() -> String? {
        guard phase == .result, let previewText else { return nil }
        let kept = previewText
        dismiss()
        return kept
    }

    /// Discard shares the same rollback boundary as ending the session.
    /// The host keeps owning the committed text, so dismissal only clears
    /// the preview, request, and prompt field.
    func dismiss() {
        playback?.cancel()
        playback = nil
        generation = UUID()
        previewText = nil
        request = nil
        prompt = ""
        errorMessage = nil
        phase = .idle
    }

    private func begin(_ request: QuickActionsPillRequest, source: String) {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            errorMessage = "Enter a prompt before using quick actions."
            return
        }
        originalSnapshot = source
        errorMessage = nil
        playback?.cancel()
        let token = UUID()
        generation = token
        self.request = request
        previewText = nil
        phase = .thinking(request.busyLabel)

        playback = Task { [weak self] in
            do {
                var didStream = false
                let emptyStream = AsyncThrowingStream<String, Error> { $0.finish() }
                let stream = self?.generate(request, source) ?? emptyStream
                for try await partial in stream {
                    try Task.checkCancellation()
                    guard self?.generation == token else { return }
                    self?.phase = .streaming(request.busyLabel)
                    self?.previewText = partial
                    didStream = true
                }
                try Task.checkCancellation()
                guard self?.generation == token else { return }
                guard didStream, self?.previewText != nil else {
                    throw QuickActionsRewriteError.emptyResponse
                }
                self?.phase = .result
                self?.playback = nil
            } catch is CancellationError {
                // Dismissal or a new request owns the next state.
            } catch {
                guard self?.generation == token else { return }
                self?.previewText = nil
                self?.request = nil
                self?.phase = .idle
                self?.errorMessage = error.localizedDescription
                self?.playback = nil
            }
        }
    }
}

typealias QuickActionsPillRequest = QuickActionsPillViewModel.Request
