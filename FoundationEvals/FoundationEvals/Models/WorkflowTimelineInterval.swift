import Foundation

/// Keeps measured timing separate from the minimum visible solid bar used for rendering.
struct WorkflowTimelineInterval {
    let offset: Double
    let width: Double
    let displayOffset: Double
    let displayWidth: Double

    init(start: Double, end: Double, extent: Double, width: Double) {
        guard start.isFinite, end.isFinite, extent.isFinite, width.isFinite,
              start >= 0, end >= start, extent > 0, width >= 0 else {
            self.offset = 0
            self.width = 0
            self.displayOffset = 0
            self.displayWidth = 0
            return
        }
        let measuredOffset = start / extent * width
        let measuredWidth = (end - start) / extent * width
        guard measuredOffset.isFinite, measuredWidth.isFinite else {
            self.offset = 0
            self.width = 0
            self.displayOffset = 0
            self.displayWidth = 0
            return
        }
        self.offset = measuredOffset
        self.width = measuredWidth
        // Even instantaneous steps remain visible. Clamp at the right edge so the
        // final scoring step is not clipped out of the timeline.
        self.displayWidth = min(width, max(2, measuredWidth))
        self.displayOffset = min(measuredOffset, width - displayWidth)
    }
}
