import SwiftUI

/// Inline quick actions for a case prompt: rewrite, shorten, tone, and grammar
/// revisions stream into a preview the user explicitly keeps or discards.
struct PromptQuickActionsSection: View {
    @Binding var prompt: String
    let isDisabled: Bool
    @State private var model = QuickActionsPillViewModel()

    /// The host binding is checked and committed synchronously on the main actor.
    /// Keeping this boundary shared with tests prevents stale preview writes.
    @MainActor
    static func keepRevision(_ model: QuickActionsPillViewModel, into prompt: Binding<String>) {
        if let kept = model.keep(source: prompt.wrappedValue) {
            prompt.wrappedValue = kept
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickActionsPill(
                primaryActions: QuickActionsPromptCatalog.primary,
                additionalActions: QuickActionsPromptCatalog.additional,
                prompt: $model.prompt,
                phase: model.phase,
                onAction: { model.select($0, source: prompt) },
                onSubmit: { model.submit(source: prompt) },
                onKeep: { Self.keepRevision(model, into: $prompt) },
                onDiscard: { model.dismiss() },
                onRetry: { model.retry(source: prompt) }
            )
            .disabled(isDisabled)
            .accessibilityIdentifier("Prompt quick actions")

            if let preview = model.previewText, !preview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.phase == .result ? "Suggested revision" : "Revising…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(preview)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .background(.background, in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("Suggested prompt revision")
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { model.dismiss() }
    }
}
