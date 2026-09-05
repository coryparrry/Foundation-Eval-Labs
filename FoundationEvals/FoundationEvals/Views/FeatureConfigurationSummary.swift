import SwiftUI

struct FeatureConfigurationSummary: View {
    let configuration: EvaluationFeatureConfiguration

    var body: some View {
        DisclosureGroup("Foundation Models configuration") {
            VStack(alignment: .leading, spacing: 12) {
                FeatureConfigurationFlags(
                    profile: configuration.profile,
                    prewarm: configuration.prewarm,
                    streamResponse: configuration.streamResponse
                )

                Divider()

                FeatureOutputConfiguration(fields: configuration.outputFields)

                Divider()

                FeatureToolConfiguration(tools: configuration.tools)
            }
            .padding(.top, 10)
        }
        .font(.callout)
    }
}

private struct FeatureConfigurationFlags: View {
    let profile: EvaluationProfileConfiguration
    let prewarm: Bool
    let streamResponse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FeatureConfigurationRow("Profile") {
                if profile.enabled {
                    Text(profile.name)
                } else {
                    Text("Disabled")
                }
            }

            if profile.enabled {
                FeatureConfigurationRow("First transition") {
                    if profile.requireToolFirst {
                        Text("Tool required")
                    } else {
                        Text("Model chooses")
                    }
                }
                FeatureConfigurationRow("After-tool instructions") {
                    if profile.afterToolInstructions.isEmpty {
                        Text("Default transition")
                    } else {
                        Text("Configured")
                    }
                }
            }

            FeatureConfigurationRow("Prewarm") {
                if prewarm {
                    Text("Enabled")
                } else {
                    Text("Disabled")
                }
            }
            FeatureConfigurationRow("Streaming") {
                if streamResponse {
                    Text("Enabled")
                } else {
                    Text("Disabled")
                }
            }
        }
    }
}

private struct FeatureOutputConfiguration: View {
    let fields: [EvaluationSchemaField]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Response format")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if fields.isEmpty {
                Text("Text")
            } else {
                ForEach(fields) { field in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(field.name)
                            .fontWeight(.medium)
                        Text(typeTitle(for: field.type))
                            .foregroundStyle(.secondary)
                        if field.isOptional {
                            Text("Optional")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func typeTitle(for type: EvaluationSchemaFieldType) -> LocalizedStringResource {
        switch type {
        case .string: "Text"
        case .integer: "Integer"
        case .number: "Number"
        case .boolean: "True or false"
        }
    }
}

private struct FeatureToolConfiguration: View {
    let tools: [EvaluationCustomToolDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom tools")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if tools.isEmpty {
                Text("None")
            } else {
                ForEach(tools) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(tool.name)
                                .fontWeight(.medium)
                            Text(modeTitle(for: tool.mode))
                                .foregroundStyle(.secondary)
                        }

                        if tool.mode == .localHTTP {
                            Text(tool.endpoint)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 8))
                }
            }
        }
    }

    private func modeTitle(for mode: EvaluationCustomToolMode) -> LocalizedStringResource {
        switch mode {
        case .fixture: "Fixture"
        case .localHTTP: "Local HTTP"
        }
    }
}

private struct FeatureConfigurationRow<Value: View>: View {
    let label: LocalizedStringResource
    @ViewBuilder let value: Value

    init(
        _ label: LocalizedStringResource,
        @ViewBuilder value: () -> Value
    ) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            value
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
