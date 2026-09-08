import Testing
@testable import FoundationEvals

struct WorkflowTimelineIntervalTests {
    @Test func sequentialSetupIntervalsDoNotBecomeOverlappingBars() {
        let setup = WorkflowTimelineInterval(start: 0, end: 3, extent: 4_120, width: 560)
        let history = WorkflowTimelineInterval(start: 4.1, end: 4.6, extent: 4_120, width: 560)
        let prompt = WorkflowTimelineInterval(start: 4.6, end: 706, extent: 4_120, width: 560)
        #expect(setup.width < 1)
        #expect(history.width < 1)
        #expect(setup.offset + setup.width < history.offset)
        #expect(abs(history.offset + history.width - prompt.offset) < 0.000001)
        let zoomed = WorkflowTimelineInterval(start: 4.1, end: 4.6, extent: 4_120, width: 56_000)
        #expect(abs(zoomed.offset - history.offset * 100) < 0.000001)
        #expect(abs(zoomed.width - history.width * 100) < 0.000001)
    }

    @Test func zeroLengthAndUnavailableTimelineIntervalsAreNotInvented() {
        #expect(WorkflowTimelineInterval(start: 3, end: 3, extent: 100, width: 500).width == 0)
        #expect(WorkflowTimelineInterval(start: 0, end: 3, extent: 0, width: 500).width == 0)
        #expect(WorkflowTimelineInterval(start: .nan, end: 3, extent: 100, width: 500).width == 0)
    }

    @Test func shortAndInstantaneousStepsKeepVisibleSolidBarDimensions() {
        let short = WorkflowTimelineInterval(start: 4.5, end: 5, extent: 2_290, width: 560)
        #expect(short.width > 0 && short.width < 1)
        #expect(short.displayWidth == 2)
        #expect(short.displayOffset == short.offset)

        let instantaneous = WorkflowTimelineInterval(start: 100, end: 100, extent: 2_290, width: 560)
        #expect(instantaneous.width == 0)
        #expect(instantaneous.displayWidth == 2)
        #expect(instantaneous.displayOffset == instantaneous.offset)
    }

    @Test func finalScoringBarRemainsInsideTimeline() {
        let scoring = WorkflowTimelineInterval(start: 2_289.6, end: 2_290, extent: 2_290, width: 560)
        #expect(scoring.offset > 558)
        #expect(scoring.displayOffset == 558)
        #expect(scoring.displayWidth == 2)
        #expect(scoring.displayOffset + scoring.displayWidth == 560)

        let endpoint = WorkflowTimelineInterval(start: 2_290, end: 2_290, extent: 2_290, width: 560)
        #expect(endpoint.offset == 560)
        #expect(endpoint.displayOffset == 558)
        #expect(endpoint.displayWidth == 2)
    }

    @Test func zeroAndNarrowCanvasNeverRenderOutsideAvailableWidth() {
        for canvasWidth in [0.0, 0.5, 1.0, 2.0] {
            let interval = WorkflowTimelineInterval(start: 99, end: 100, extent: 100, width: canvasWidth)
            #expect(interval.displayWidth == canvasWidth)
            #expect(interval.displayOffset == 0)
        }
    }

    @Test func zoomRevealsMeasuredDurationWithoutChangingMinimumBarSize() {
        let fit = WorkflowTimelineInterval(start: 4, end: 5, extent: 1_000, width: 500)
        let zoom = WorkflowTimelineInterval(start: 4, end: 5, extent: 1_000, width: 5_000)
        #expect(fit.displayWidth == 2)
        #expect(zoom.displayWidth == 5)
        #expect(zoom.displayWidth == zoom.width)
        #expect(zoom.displayOffset == fit.offset * 10)
    }

    @Test func longAndParentIntervalsRetainTheirMeasuredDimensions() {
        let parent = WorkflowTimelineInterval(start: 0, end: 1_000, extent: 1_000, width: 500)
        let child = WorkflowTimelineInterval(start: 200, end: 600, extent: 1_000, width: 500)
        #expect(parent.displayOffset == 0)
        #expect(parent.displayWidth == 500)
        #expect(child.displayOffset == 100)
        #expect(child.displayWidth == 200)
    }

    @Test func invalidInputsDoNotProducePhantomBars() {
        let invalid: [(Double, Double, Double, Double)] = [
            (-1, 3, 100, 500), (4, 3, 100, 500), (0, 3, 0, 500),
            (0, 3, -100, 500), (0, 3, 100, -1),
            (.nan, 3, 100, 500), (0, .nan, 100, 500),
            (0, 3, .nan, 500), (0, 3, 100, .nan),
            (.infinity, .infinity, 100, 500), (0, .infinity, 100, 500),
            (0, 3, .infinity, 500), (0, 3, 100, .infinity),
            (1, 2, .leastNonzeroMagnitude, 500),
        ]
        for (start, end, extent, width) in invalid {
            let interval = WorkflowTimelineInterval(start: start, end: end, extent: extent, width: width)
            #expect(interval.offset == 0)
            #expect(interval.width == 0)
            #expect(interval.displayOffset == 0)
            #expect(interval.displayWidth == 0)
        }
    }
}
