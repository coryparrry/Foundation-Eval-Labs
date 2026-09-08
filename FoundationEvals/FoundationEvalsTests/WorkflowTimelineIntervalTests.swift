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

}
