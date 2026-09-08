import SwiftUI

/// The toolbar supplies the surrounding capsule; keep its content clear of the rounded ends.
struct RunToolbarProgress: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .frame(width: 90)
            Text("\(completed) of \(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Evaluation progress")
        .accessibilityValue("\(completed) of \(total)")
    }
}
