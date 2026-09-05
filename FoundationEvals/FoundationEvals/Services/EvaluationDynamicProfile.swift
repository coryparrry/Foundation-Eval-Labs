import FoundationModels

extension SessionPropertyValues {
    @SessionPropertyEntry
    var evaluationProfileReceivedToolOutput = false
}

actor EvaluationProfileRecorder {
    private var events: [String] = []
    private(set) var transitioned = false

    func recordActivation(_ profileName: String) {
        events.append("Activated profile: \(profileName)")
    }

    func recordToolOutput(toolName: String) {
        events.append("Tool output received: \(toolName)")
    }

    func recordTransition(_ profileName: String) {
        transitioned = true
        recordActivation("\(profileName) · after tool")
    }

    func snapshot() -> [String] {
        events
    }
}

struct EvaluationDynamicProfile: LanguageModelSession.DynamicProfile {
    private let model: any LanguageModel
    private let instructions: String
    private let tools: [any Tool]
    private let configuration: EvaluationProfileConfiguration
    private let recorder: EvaluationProfileRecorder

    @LanguageModelSession.SessionProperty(\.evaluationProfileReceivedToolOutput)
    private var receivedToolOutput

    private var afterToolInstructions: String {
        [instructions, configuration.afterToolInstructions]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var body: some LanguageModelSession.DynamicProfile {
        if receivedToolOutput {
            LanguageModelSession.Profile {
                Instructions(afterToolInstructions)
            }
            .model(model)
            .toolCallingMode(.disallowed)
            .onActivate {
                await recorder.recordTransition(configuration.name)
            }
        } else {
            LanguageModelSession.Profile {
                Instructions(instructions)
                tools
            }
            .model(model)
            .toolCallingMode(configuration.requireToolFirst ? .required : .allowed)
            .onActivate {
                await recorder.recordActivation(configuration.name)
            }
            .onToolOutput { call, _ in
                await recorder.recordToolOutput(toolName: call.toolName)
                receivedToolOutput = true
            }
        }
    }

    static func makeSession(
        model: some LanguageModel,
        instructions: String,
        tools: [any Tool],
        configuration: EvaluationProfileConfiguration,
        recorder: EvaluationProfileRecorder
    ) -> LanguageModelSession {
        LanguageModelSession(
            profile: EvaluationDynamicProfile(
                model: model,
                instructions: instructions,
                tools: tools,
                configuration: configuration,
                recorder: recorder
            )
        )
    }
}
