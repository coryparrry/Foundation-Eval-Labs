import Foundation
import Testing
#if canImport(SwiftUI)
import SwiftUI
#endif
@testable import FoundationEvals

private enum QuickActionsStubError: Error {
    case generationFailed
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

@Suite(.timeLimit(.minutes(1)))
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

    @Test func disabledActionDoesNotStartARequest() {
        let model = QuickActionsPillViewModel(generate: stub())
        let action = QuickActionsPillAction(
            id: "explain", title: "Explain", systemImage: "questionmark.bubble",
            busyLabel: "Explaining", isEnabled: false
        )
        #expect(model.select(action, source: "Some prompt") == nil)
        #expect(model.phase == .idle)
        #expect(model.request == nil)
    }

    @Test func emptySourceExplainsInsteadOfGenerating() {
        let model = QuickActionsPillViewModel(generate: stub())
        #expect(model.select(QuickActionsPromptCatalog.primary[0], source: "   ") == nil)
        #expect(model.phase == .idle)
        #expect(model.errorMessage != nil)
    }

    @Test func selectStreamsPreviewThenKeepCommitsAndResets() async throws {
        let model = QuickActionsPillViewModel(generate: stub(chunks: ["revised", "revised prompt"]))
        let task = try #require(model.select(QuickActionsPromptCatalog.primary[0], source: "Original prompt"))
        await task.value
        #expect(model.phase == .result)
        #expect(model.previewText == "revised prompt")
        let kept = model.keep(source: "Original prompt")
        #expect(kept == "revised prompt")
        #expect(model.phase == .idle)
        #expect(model.previewText == nil)
        #expect(model.request == nil)
    }

    @Test func dismissClearsPreviewWithoutCommitting() async throws {
        let model = QuickActionsPillViewModel(generate: stub())
        let task = try #require(model.select(QuickActionsPromptCatalog.primary[0], source: "Original prompt"))
        await task.value
        #expect(model.phase == .result)
        model.dismiss()
        #expect(model.phase == .idle)
        #expect(model.previewText == nil)
        #expect(model.prompt.isEmpty)
    }

    @Test func retryRegeneratesAfterResult() async throws {
        let calls = Locked(0)
        let model = QuickActionsPillViewModel(generate: { _, _ in
            let attempt = calls.withLock { value in value += 1; return value }
            return AsyncThrowingStream { continuation in
                continuation.yield("attempt \(attempt)")
                continuation.finish()
            }
        })
        let first = try #require(model.select(QuickActionsPromptCatalog.primary[0], source: "Original prompt"))
        await first.value
        let second = try #require(model.retry(source: "Original prompt"))
        await second.value
        #expect(model.phase == .result)
        #expect(model.previewText == "attempt 2")
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func submitUsesCustomPromptRequest() async throws {
        let seenID = Locked<String?>(nil)
        let seenPrompt = Locked<String?>(nil)
        let model = QuickActionsPillViewModel(generate: { request, _ in
            seenID.withLock { $0 = request.id }
            seenPrompt.withLock { $0 = request.prompt }
            return AsyncThrowingStream { continuation in
                continuation.yield("custom revision")
                continuation.finish()
            }
        })
        model.prompt = "  Make it shorter  "
        let task = try #require(model.submit(source: "Original prompt"))
        await task.value
        #expect(model.phase == .result)
        #expect(seenID.withLock { $0 } == "prompt")
        #expect(seenPrompt.withLock { $0 } == "Make it shorter")
    }

    @Test func generationFailureReturnsToIdleWithMessage() async throws {
        let model = QuickActionsPillViewModel(generate: stub(chunks: [], error: QuickActionsStubError.generationFailed))
        let task = try #require(model.select(QuickActionsPromptCatalog.primary[0], source: "Original prompt"))
        await task.value
        #expect(model.errorMessage != nil)
        #expect(model.phase == .idle)
        #expect(model.previewText == nil)
    }

    @Test func editedSourceIsNotOverwrittenAndRetryUsesCurrentSource() async throws {
        let model = QuickActionsPillViewModel(generate: { _, source in
            AsyncThrowingStream { continuation in
                continuation.yield("Revised: \(source)")
                continuation.finish()
            }
        })
        let first = try #require(model.select(QuickActionsPromptCatalog.primary[0], source: "A"))
        await first.value
        #expect(model.keep(source: "B") == nil)
        #expect(model.errorMessage != nil)
        #expect(model.phase == .result)
        #expect(model.previewText == "Revised: A")
        let retry = try #require(model.retry(source: "B"))
        await retry.value
        #expect(model.originalSnapshot == "B")
        #expect(model.keep(source: "B") == "Revised: B")
    }

    #if canImport(SwiftUI)
    @Test func hostBindingPreservesEditsMadeBeforeKeep() async throws {
        var source = "A"
        let binding = Binding(get: { source }, set: { source = $0 })
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        let model = QuickActionsPillViewModel(generate: { _, _ in pair.stream })
        let task = try #require(model.select(QuickActionsPromptCatalog.primary[0], source: binding.wrappedValue))
        binding.wrappedValue = "B: important new constraint"
        pair.continuation.yield("Revision based on A")
        pair.continuation.finish()
        await task.value
        PromptQuickActionsSection.keepRevision(model, into: binding)
        #expect(source == "B: important new constraint")
        #expect(model.phase == .result)
        #expect(model.errorMessage != nil)
        model.dismiss()
        #expect(source == "B: important new constraint")
    }
    #endif

    @Test func dismissedSessionCannotPublishIntoANewSession() async throws {
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        let model = QuickActionsPillViewModel(generate: { _, source in
            if source == "A" { return pair.stream }
            return AsyncThrowingStream { continuation in
                continuation.yield("B revision")
                continuation.finish()
            }
        })
        let first = try #require(model.select(QuickActionsPromptCatalog.primary[0], source: "A"))
        model.dismiss()
        let second = try #require(model.select(QuickActionsPromptCatalog.primary[0], source: "B"))
        pair.continuation.yield("obsolete A revision")
        pair.continuation.finish()
        await first.value
        await second.value
        #expect(model.previewText == "B revision")
        #expect(model.keep(source: "B") == "B revision")
    }

    @Test func cancellingCompletionHandleDoesNotLeaveBusyState() async throws {
        let pair = AsyncThrowingStream<String, Error>.makeStream()
        let model = QuickActionsPillViewModel(generate: { _, _ in pair.stream })
        let task = try #require(model.select(QuickActionsPromptCatalog.primary[0], source: "A"))
        task.cancel()
        await task.value
        #expect(model.phase == .idle)
        #expect(!model.isBusy)
        #expect(model.previewText == nil)
        pair.continuation.finish()
    }
}
