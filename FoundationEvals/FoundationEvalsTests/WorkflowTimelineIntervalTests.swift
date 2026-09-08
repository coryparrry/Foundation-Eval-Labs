import Testing
@testable import FoundationEvals

struct WorkflowTimelineIntervalTests {
    private let boundaries = [0.0, 0.02, 1.0, 1.1, 1.9, 3.1, 3.6, 3.7, 677, 22_021.9, 22_022]

    @Test func sequentialSubmillisecondSpansDoNotVisuallyOverlap() {
        let scale = WorkflowTimelineScale(boundaries: boundaries, extent: 22_022, width: 560)
        let restore = WorkflowTimelineInterval(start: 1.1, end: 1.9, scale: scale)
        let history = WorkflowTimelineInterval(start: 3.1, end: 3.6, scale: scale)
        let prompt = WorkflowTimelineInterval(start: 3.7, end: 677, scale: scale)
        #expect(restore.displayWidth >= 15.99)
        #expect(history.displayWidth >= 15.99)
        #expect(restore.displayOffset + restore.displayWidth < history.displayOffset)
        #expect(history.displayOffset + history.displayWidth < prompt.displayOffset)
        #expect(scale.position(at: 677) == prompt.displayOffset + prompt.displayWidth)
    }

    @Test func sharedBoundariesAndRealOverlapsRemainAligned() {
        let scale = WorkflowTimelineScale(boundaries: boundaries, extent: 22_022, width: 560)
        let preparation = WorkflowTimelineInterval(start: 0.02, end: 677, scale: scale)
        let setup = WorkflowTimelineInterval(start: 1, end: 3.1, scale: scale)
        let child = WorkflowTimelineInterval(start: 1.1, end: 1.9, scale: scale)
        let generation = WorkflowTimelineInterval(start: 677, end: 22_021.9, scale: scale)
        #expect(preparation.displayOffset < setup.displayOffset)
        #expect(setup.displayOffset < child.displayOffset)
        #expect(child.displayOffset + child.displayWidth < setup.displayOffset + setup.displayWidth)
        #expect(preparation.displayOffset + preparation.displayWidth == generation.displayOffset)
        let parent = WorkflowTimelineInterval(start: 0, end: 22_022, scale: scale)
        #expect(parent.displayOffset == 0)
        #expect(parent.displayWidth == 560)
    }

    @Test func axisLabelsInvertTheSameScaleAsTheBars() {
        let scale = WorkflowTimelineScale(boundaries: boundaries, extent: 22_022, width: 560)
        for time in boundaries + [1.5, 400, 11_000, 22_021.95] {
            #expect(abs(scale.time(at: scale.position(at: time)) - time) < 0.000001)
        }
        // Expanded early time must not be labeled as a quarter of the real duration.
        #expect(scale.time(at: 140) < 22_022 / 4)
        #expect(scale.time(at: 560) == 22_022)
    }

    @Test func alreadyReadableTimelinesKeepTheirLinearScale() {
        let scale = WorkflowTimelineScale(boundaries: [0, 200, 600, 1_000], extent: 1_000, width: 500)
        let child = WorkflowTimelineInterval(start: 200, end: 600, scale: scale)
        #expect(child.displayOffset == 100)
        #expect(child.displayWidth == 200)
    }

    @Test func endOfRunStepsStayVisibleWithoutMovingIntoEarlierSteps() {
        let scale = WorkflowTimelineScale(boundaries: boundaries, extent: 22_022, width: 560)
        let scoring = WorkflowTimelineInterval(start: 22_021.9, end: 22_022, scale: scale)
        #expect(scoring.displayWidth >= 15.99)
        #expect(scoring.displayOffset == scale.position(at: 22_021.9))
        #expect(scoring.displayOffset + scoring.displayWidth == 560)
        let instant = WorkflowTimelineInterval(start: 22_022, end: 22_022, scale: scale)
        #expect(instant.displayWidth == 2)
        #expect(instant.displayOffset + instant.displayWidth == 560)
    }

    @Test func narrowAndDenseTimelinesStayBoundedAndOrdered() {
        for width in [0.0, 0.5, 43, 120, 560, 1_400] {
            let times = (0...2_000).map { Double($0) / 100 }
            let scale = WorkflowTimelineScale(boundaries: times, extent: 20, width: width)
            #expect(scale.positions.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= width })
            for (left, right) in zip(scale.positions, scale.positions.dropFirst()) {
                #expect(left <= right)
            }
            #expect(scale.position(at: 20) == width)
        }
    }

    @Test func denseEarlyEventsExpandWithoutPushingLongOperationsOffscreen() {
        let times = (0...2_000).map { Double($0) / 100 }
        for width in [43.0, 120, 560] {
            let scale = WorkflowTimelineScale(boundaries: times, extent: 22_022, width: width)
            #expect(scale.position(at: 20) > width / 3)
            #expect(width - scale.position(at: 20) > width / 3)
            #expect(scale.positions.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= width })
            for (left, right) in zip(scale.positions, scale.positions.dropFirst()) {
                #expect(left < right)
            }
        }
    }

    @Test func boundaryOrderDuplicatesAndInvalidValuesDoNotChangeLayout() {
        let clean = WorkflowTimelineScale(boundaries: boundaries, extent: 22_022, width: 560)
        let noisy = WorkflowTimelineScale(boundaries: boundaries.reversed() + boundaries + [.nan, .infinity, -1, 90_000],
            extent: 22_022, width: 560)
        #expect(clean.times == noisy.times)
        #expect(clean.positions == noisy.positions)
    }

    @Test func invalidTimingOrGeometryDoesNotInventBars() {
        for extent in [0.0, -1, .nan, .infinity] {
            let scale = WorkflowTimelineScale(boundaries: boundaries, extent: extent, width: 560)
            #expect(WorkflowTimelineInterval(start: 0, end: 3, scale: scale).displayWidth == 0)
            #expect(WorkflowTimelineInterval(start: 0, end: 0, scale: scale).displayWidth == 0)
        }
        for width in [0.0, -1, .nan, .infinity] {
            let scale = WorkflowTimelineScale(boundaries: boundaries, extent: 22_022, width: width)
            #expect(WorkflowTimelineInterval(start: 0, end: 3, scale: scale).displayWidth == 0)
        }
        let scale = WorkflowTimelineScale(boundaries: boundaries, extent: 22_022, width: 560)
        for (start, end) in [(-1.0, 3.0), (4, 3), (.nan, 3), (0, .nan), (0, .infinity), (0, 30_000)] {
            let interval = WorkflowTimelineInterval(start: start, end: end, scale: scale)
            #expect(interval.displayOffset == 0)
            #expect(interval.displayWidth == 0)
        }
    }
}
