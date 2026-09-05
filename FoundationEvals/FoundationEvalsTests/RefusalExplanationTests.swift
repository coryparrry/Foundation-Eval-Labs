import Foundation
import FoundationModels
import Testing
@testable import FoundationEvals

struct RefusalExplanationTests {
    @Test func refusalExplanationIsBoundedAndPersists() async throws {
        let refusal = LanguageModelError.Refusal(
            explanation: String(repeating: "A", count: 64),
            debugDescription: "Test refusal"
        )

        let trace = try #require(await EvaluationRefusalTrace.capture(
            from: LanguageModelError.refusal(refusal),
            maximumCharacters: 12
        ))
        let restored = try JSONDecoder().decode(
            EvaluationRefusalTrace.self,
            from: JSONEncoder().encode(trace)
        )

        #expect(trace.explanation == String(repeating: "A", count: 12))
        #expect(trace.explanationWasTruncated)
        #expect(!trace.explanationGenerationFailed)
        #expect(restored == trace)
    }

    @Test func refusalExplanationFailureIsRecordedWithoutReplacingTheRefusal() async {
        struct ExplanationError: LocalizedError {
            var errorDescription: String? { "Explanation generation failed" }
        }

        let trace = await EvaluationRefusalTrace.captureExplanation {
            throw ExplanationError()
        }

        #expect(trace.explanation == nil)
        #expect(trace.explanationGenerationFailed)
        #expect(trace.explanationFailureMessage == "Explanation generation failed")
    }

    @Test func refusalExplanationTimesOut() async {
        let operationStarted = AsyncStream<Void>.makeStream()
        let timeoutRelease = AsyncStream<Void>.makeStream()
        let operationCancelled = AsyncStream<Void>.makeStream()
        let capture = Task {
            await EvaluationRefusalTrace.captureExplanation(
                timeout: .seconds(60),
                timeoutWait: { _ in
                    var iterator = timeoutRelease.stream.makeAsyncIterator()
                    _ = await iterator.next()
                }
            ) {
                operationStarted.continuation.yield(())
                do {
                    try await Task.sleep(for: .seconds(60))
                    return "Too late"
                } catch {
                    operationCancelled.continuation.yield(())
                    throw error
                }
            }
        }

        var operationStartIterator = operationStarted.stream.makeAsyncIterator()
        _ = await operationStartIterator.next()
        timeoutRelease.continuation.yield(())
        timeoutRelease.continuation.finish()
        let trace = await capture.value
        var operationCancellationIterator = operationCancelled.stream.makeAsyncIterator()
        _ = await operationCancellationIterator.next()

        #expect(trace.explanation == nil)
        #expect(trace.explanationGenerationFailed)
        #expect(trace.explanationFailureMessage == "Refusal explanation generation timed out.")
    }

    @Test func cancelledCaptureDoesNotStartExplanationGeneration() async {
        actor AttemptRecorder {
            private(set) var count = 0
            func record() { count += 1 }
        }

        let recorder = AttemptRecorder()
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            var iterator = gate.stream.makeAsyncIterator()
            _ = await iterator.next()
            return await EvaluationRefusalTrace.captureExplanation {
                await recorder.record()
                return "Unexpected"
            }
        }
        task.cancel()
        gate.continuation.yield(())
        gate.continuation.finish()

        let trace = await task.value
        #expect(await recorder.count == 0)
        #expect(trace.explanationGenerationFailed)
        #expect(trace.explanationFailureMessage == "Refusal explanation generation was cancelled.")
    }
}
