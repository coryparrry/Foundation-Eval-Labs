import SwiftUI

/// Keeps all phase content structurally stable and interpolates the capsule's
/// width directly from SwiftUI's layout proposal and each phase's ideal size.
struct QuickActionsPillPhaseLayout: Layout {
    var position: CGFloat

    var animatableData: CGFloat {
        get { position }
        set { position = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 3 else { return .zero }

        let availableWidth = resolvedWidth(for: proposal, subviews: subviews)
        let widths = phaseWidths(availableWidth: availableWidth, subviews: subviews)
        let clampedPosition = min(max(position, 0), 2)
        let lowerIndex = Int(clampedPosition.rounded(.down))
        let upperIndex = min(lowerIndex + 1, 2)
        let progress = clampedPosition - CGFloat(lowerIndex)
        let width = widths[lowerIndex] + (widths[upperIndex] - widths[lowerIndex]) * progress
        let idealHeight = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0

        return CGSize(width: width, height: proposal.height ?? idealHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 3 else { return }

        let proposedWidth = proposal.width.map { $0.isFinite ? $0 : bounds.width } ?? bounds.width
        let widths = phaseWidths(availableWidth: proposedWidth, subviews: subviews)

        for index in subviews.indices {
            let width = widths[index]
            subviews[index].place(
                at: CGPoint(x: bounds.midX - width / 2, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }

    private func phaseWidths(
        availableWidth: CGFloat,
        subviews: Subviews
    ) -> [CGFloat] {
        [
            availableWidth,
            min(availableWidth, subviews[1].sizeThatFits(.unspecified).width),
            min(availableWidth, subviews[2].sizeThatFits(.unspecified).width)
        ]
    }

    private func resolvedWidth(
        for proposal: ProposedViewSize,
        subviews: Subviews
    ) -> CGFloat {
        guard let proposedWidth = proposal.width, proposedWidth.isFinite else {
            return subviews[0].sizeThatFits(.unspecified).width
        }
        return proposedWidth
    }
}
