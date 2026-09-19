import Foundation
import FoundationEvalsDeveloper
import FoundationModels
import Observation
import SwiftUI

@main
struct DeveloperRunnerTestHostApp: App {
    @State private var harness = DeveloperRunnerTestHarness()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Group {
                    if harness.isReady {
                        DeveloperRunnerView(service: harness.service)
                    } else {
                        ProgressView("Registering verification features…")
                    }
                }
                .task { await harness.prepareIfNeeded() }
            }
        }
    }
}

@MainActor
@Observable
private final class DeveloperRunnerTestHarness {
    let registry: DeveloperFeatureRegistry
    let service: DeveloperRunnerService
    private(set) var isReady = false

    init() {
        let registry = DeveloperFeatureRegistry()
        let identity = DeveloperRunnerIdentity.current(
            id: Self.persistedRunnerID(),
            displayName: "Foundation Evals verification host"
        )
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.registry = registry
        service = DeveloperRunnerService(
            identity: identity,
            registry: registry,
            trustStoreURL: support
                .appending(path: "FoundationEvalsVerification", directoryHint: .isDirectory)
                .appending(path: "runner-trust.json")
        )
    }

    func prepareIfNeeded() async {
        guard !isReady else { return }

        await registry.registerTextFeature(
            id: "verification.echo",
            displayName: "Deterministic echo",
            version: "1",
            capabilityNames: ["deterministic", "typed-input"]
        ) { input, context in
            try context.checkCancellation()
            return DeveloperFeatureOutput(
                response: input.prompt,
                usage: .init(inputTokens: input.prompt.split(whereSeparator: \.isWhitespace).count),
                metadata: ["execution": "deterministic-fixture"]
            )
        }

        await registry.registerTextFeature(
            id: "verification.slow",
            displayName: "Cancellable slow response",
            version: "1",
            capabilityNames: ["cancellation", "deadline"]
        ) { input, context in
            for _ in 0..<300 {
                try context.checkCancellation()
                try await Task.sleep(for: .milliseconds(100))
            }
            return DeveloperFeatureOutput(response: input.prompt)
        }

        await registry.registerTextFeature(
            id: "verification.timeout",
            displayName: "Deadline exceeded fixture",
            version: "1",
            capabilityNames: ["deadline"]
        ) { _, context in
            try await Task.sleep(for: .milliseconds(500))
            try context.checkCancellation()
            throw DeveloperExecutionFailure(
                code: .deadlineExceeded,
                message: "The verification fixture exceeded its deadline."
            )
        }

        await registry.registerTextFeature(
            id: "verification.foundation-model",
            displayName: "Apple Foundation Model",
            version: "1",
            capabilityNames: ["foundation-models", "on-device-generation"]
        ) { input, context in
            try context.checkCancellation()
            guard case .available = SystemLanguageModel.default.availability else {
                throw DeveloperExecutionFailure(
                    code: .executionFailed,
                    message: "The Apple on-device model is unavailable: \(SystemLanguageModel.default.availability)."
                )
            }
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: Instructions(input.instructions)
            )
            let response = try await session.respond(to: Prompt(input.prompt))
            try context.checkCancellation()
            let usage: DeveloperFeatureUsage
            if #available(iOS 27.0, macOS 27.0, *) {
                usage = .init(
                    inputTokens: response.usage.input.totalTokenCount,
                    outputTokens: response.usage.output.totalTokenCount
                )
            } else {
                usage = .init()
            }
            return DeveloperFeatureOutput(
                response: response.content,
                usage: usage,
                metadata: ["execution": "apple-foundation-model"]
            )
        }

        await service.refreshFeatures()
        isReady = true
        if ProcessInfo.processInfo.arguments.contains("--auto-pair") {
            await service.beginPairing()
        }
    }

    private static func persistedRunnerID() -> UUID {
        let key = "FoundationEvalsVerificationRunnerID"
        if let value = UserDefaults.standard.string(forKey: key),
           let id = UUID(uuidString: value) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }
}
