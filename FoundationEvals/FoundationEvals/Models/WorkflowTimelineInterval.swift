import Foundation

/// Exact measured placement. Subpixel intervals are marked by the view, never widened.
struct WorkflowTimelineInterval {
    let offset: Double
    let width: Double

    init(start: Double, end: Double, extent: Double, width: Double) {
        guard start.isFinite, end.isFinite, extent.isFinite, width.isFinite,
              start >= 0, end >= start, extent > 0, width >= 0 else {
            self.offset = 0
            self.width = 0
            return
        }
        self.offset = start / extent * width
        self.width = (end - start) / extent * width
    }
}
