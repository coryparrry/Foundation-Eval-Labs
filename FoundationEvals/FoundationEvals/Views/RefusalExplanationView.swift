import SwiftUI

struct RefusalExplanationView: View {
    let trace: EvaluationRefusalTrace
    var title: LocalizedStringResource = "Why the model refused"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "hand.raised.fill")
                .fontWeight(.semibold)

            if let explanation = trace.explanation {
                Text(explanation)
                    .textSelection(.enabled)
                if trace.explanationWasTruncated {
                    Text("The saved explanation was shortened to the trace limit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if trace.explanationGenerationFailed {
                Text("The model refused the request, but its explanation could not be generated.")
                if let message = trace.explanationFailureMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.25))
        }
    }
}
