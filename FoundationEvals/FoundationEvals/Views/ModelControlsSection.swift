import SwiftUI

struct ModelControlsSection: View {
    @Bindable var store: EvaluationStore

    private var configuration: EvaluationModelConfiguration {
        store.draftSuite.modelConfiguration
    }

    var body: some View {
        EditorSection(
            "Model controls",
            systemImage: "slider.horizontal.3",
            description: "Make decoding, context, and tool behavior explicit for every run."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                providerAndReasoning
                Divider()
                decodingControls
                Divider()
                contextAndToolControls
                capabilitySummary
            }
            .disabled(store.isRunning || store.isProcessingFiles)
        }
    }

    private var providerAndReasoning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Execution")
                .font(.headline)

            Label("On-device Foundation Model", systemImage: "cpu")
                .font(.body.weight(.medium))
                .accessibilityIdentifier("On-device model")

            Text("Prompts stay on this Mac. The framework chooses reasoning automatically and the run trace records any reasoning tokens or readable reasoning it returns.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var decodingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generation")
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 24) {
                LabeledContent("Sampling") {
                    Picker("Sampling", selection: $store.draftSuite.modelConfiguration.samplingMode) {
                        ForEach(EvaluationSamplingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                LabeledContent("Response limit") {
                    Picker("Response limit", selection: $store.draftSuite.modelConfiguration.maximumResponseTokens) {
                        ForEach([256, 512, 1_024, 2_048, 4_096], id: \.self) { limit in
                            Text("\(limit.formatted()) tokens").tag(limit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            if configuration.samplingMode == .topK {
                Stepper("Top K: \(configuration.topK)", value: $store.draftSuite.modelConfiguration.topK, in: 1...1_000)
            } else if configuration.samplingMode == .probability {
                LabeledContent("Probability threshold") {
                    Slider(value: $store.draftSuite.modelConfiguration.probabilityThreshold, in: 0.05...1, step: 0.05)
                        .frame(width: 180)
                    Text(configuration.probabilityThreshold.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }

            if configuration.samplingMode == .topK || configuration.samplingMode == .probability {
                Toggle("Use a fixed seed", isOn: $store.draftSuite.modelConfiguration.seedEnabled)
                if configuration.seedEnabled {
                    TextField("Seed", value: $store.draftSuite.modelConfiguration.seed, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }

            Toggle("Set temperature", isOn: $store.draftSuite.modelConfiguration.temperatureEnabled)
            if configuration.temperatureEnabled {
                LabeledContent("Temperature") {
                    Slider(value: $store.draftSuite.modelConfiguration.temperature, in: 0...1, step: 0.05)
                        .frame(width: 180)
                    Text(configuration.temperature.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }

            Text("Response limits can stop generation mid-sentence without an error. Greedy or seeded sampling improves repeatability but cannot guarantee identical output across model or OS versions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var contextAndToolControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Context and references")
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 24) {
                LabeledContent("Requested input ceiling") {
                    Picker("Requested input ceiling", selection: $store.draftSuite.modelConfiguration.maximumInputTokens) {
                        Text("Automatic").tag(Int?.none)
                        ForEach([2_048, 4_096, 8_192, 16_384, 32_768], id: \.self) { limit in
                            Text("\(limit.formatted()) tokens").tag(Int?.some(limit))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                LabeledContent("When input is too large") {
                    Picker("Context policy", selection: $store.draftSuite.modelConfiguration.contextPolicy) {
                        ForEach(EvaluationContextPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            Picker("Text references", selection: $store.draftSuite.modelConfiguration.referenceMode) {
                ForEach(EvaluationReferenceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("Text reference delivery")

            if configuration.referenceMode == .lookupTool {
                Stepper(
                    "Maximum tool calls per response: \(configuration.maximumToolCalls)",
                    value: $store.draftSuite.modelConfiguration.maximumToolCalls,
                    in: 1...4
                )
                Text(referenceToolPrivacyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Reference text is included directly. Fit reference text truncates only imported text; Require full input stops the sample instead of changing it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Instructions, prompts, images, tool definitions and outputs, responses, reasoning, and guided-generation schemas all share the selected model's context window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var referenceToolPrivacyText: String {
        let destination = configuration.provider == .onDevice
            ? "Returned excerpts stay on this Mac."
            : "Returned excerpts are sent to Apple's Private Cloud Compute as model context."
        return "The app searches imported text locally and read-only, returning at most two bounded excerpts per call. \(destination) Saved traces omit query text and returned passages."
    }

    private var capabilitySummary: some View {
        let names = store.selectedModelCapabilities.evaluationNames
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Available capabilities: \(names.isEmpty ? "none reported" : names.joined(separator: ", ")). \(store.modelStatus.detail)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9))
    }
}
