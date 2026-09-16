import Foundation
import Testing
@testable import FoundationEvals

private enum QuickActionsStubError: Error {
    case generationFailed
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

@MainActor
struct QuickActionsPillViewModelTests {
    private func stub(
        chunks: [String] = ["revised prompt"],
        error: (any Error)? = nil
    ) -> QuickActionsRewriteStreamProvider {
        { _, _ in
            AsyncThrowingStream { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                if let error { continuation.finish(throwing: error) }
                else { continuation.finish() }
            }
        }
    }

    private func waitFor(
        _ condition: () -> Bool,
        timeout: Duration = .milliseconds(2_000)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test func disabledActionDoesNotStartARequest() async {
        let model = QuickActionsPillViewModel(generate: stub())
        let action = QuickActionsPillAction(
            id: "explain", title: "Explain", systemImage: "questionmark.bubble",
            busyLabel: "Explaining", isEnabled: false
        )
        model.select(action, source: "Some prompt")
        #expect(model.phase == .idle)
        #expect(model.request == nil)
    }

    @Test func emptySourceExplainsInsteadOfGenerating() async {
        let model = QuickActionsPillViewModel(generate: stub())
        model.select(QuickActionsPromptCatalog.primary[0], source: "   ")
        #expect(model.phase == .idle)
        #expect(model.errorMessage != nil)
    }

    @Test func selectStreamsPreviewThenKeepCommitsAndResets() async {
        let model = QuickActionsPillViewModel(generate: stub(chunks: ["revised", "revised prompt"]))
        model.select(QuickActionsPromptCatalog.primary[0], source: "Original prompt")
        #expect(await waitFor({ model.phase == .result }))
        #expect(model.previewText == "revised prompt")

        let kept = model.keep()
        #expect(kept == "revised prompt")
        #expect(model.phase == .idle)
        #expect(model.previewText == nil)
        #expect(model.request == nil)
    }

    @Test func dismissClearsPreviewWithoutCommitting() async {
        let model = QuickActionsPillViewModel(generate: stub())
        model.select(QuickActionsPromptCatalog.primary[0], source: "Original prompt")
        #expect(await waitFor({ model.phase == .result }))
        model.dismiss()
        #expect(model.phase == .idle)
        #expect(model.previewText == nil)
        #expect(model.prompt.isEmpty)
    }

    @Test func retryRegeneratesAfterResult() async {
        let calls = Locked(0)
        let model = QuickActionsPillViewModel(generate: { _, _ in
            let attempt = calls.withLock { value in
                value += 1
                return value
            }
            return AsyncThrowingStream { continuation in
                continuation.yield("attempt \(attempt)")
                continuation.finish()
            }
        })
        model.select(QuickActionsPromptCatalog.primary[0], source: "Original prompt")
        #expect(await waitFor({ model.phase == .result }))
        model.retry()
        #expect(await waitFor({ model.previewText == "attempt 2" }))
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func submitUsesCustomPromptRequest() async {
        let seenID = Locked<String?>(nil)
        let seenPrompt = Locked<String?>(nil)
        let didCall = Locked(false)
        let model = QuickActionsPillViewModel(generate: { request, _ in
            seenID.withLock { $0 = request.id }
            seenPrompt.withLock { $0 = request.prompt }
            didCall.withLock { $0 = true }
            return AsyncThrowingStream { continuation in
                continuation.yield("custom revision")
                continuation.finish()
            }
        })
        model.prompt = "  Make it shorter  "
        model.submit(source: "Original prompt")
        #expect(await waitFor({ model.phase == .result }))
        #expect(didCall.withLock { $0 })
        #expect(seenID.withLock { $0 } == "prompt")
        #expect(seenPrompt.withLock { $0 } == "Make it shorter")
    }

    @Test func generationFailureReturnsToIdleWithMessage() async {
        let model = QuickActionsPillViewModel(generate: stub(chunks: [], error: QuickActionsStubError.generationFailed))
        model.select(QuickActionsPromptCatalog.primary[0], source: "Original prompt")
        #expect(await waitFor({ model.errorMessage != nil }))
        #expect(model.phase == .idle)
        #expect(model.previewText == nil)
    }
}
