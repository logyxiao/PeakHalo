import AppKit
import Testing
@testable import PeakHalo

@Suite("Notch hover hit testing")
struct NotchHoverHitTestingTests {
    @Test("Visible hover includes the top screen edge")
    func visibleHoverIncludesTopEdge() {
        let frame = NSRect(x: 100, y: 900, width: 260, height: 28)
        let pointOnTopEdge = NSPoint(x: frame.midX, y: frame.maxY)

        #expect(!frame.contains(pointOnTopEdge))
        #expect(NotchHoverHitTesting.containsVisible(pointOnTopEdge, in: frame))
    }

    @Test("Visible hover allows tiny top edge coordinate drift")
    func visibleHoverAllowsTinyTopEdgeDrift() {
        let frame = NSRect(x: 100, y: 900, width: 260, height: 28)
        let pointJustPastTopEdge = NSPoint(
            x: frame.midX,
            y: frame.maxY + NotchHoverHitTesting.topEdgeTolerance
        )

        #expect(NotchHoverHitTesting.containsVisible(pointJustPastTopEdge, in: frame))
    }

    @Test("Visible hover does not use the retained close band")
    func visibleHoverDoesNotUseRetainedBand() {
        let frame = NSRect(x: 100, y: 900, width: 260, height: 28)
        let pointInRetainedBandOnly = NSPoint(
            x: frame.midX,
            y: frame.maxY + NotchHoverHitTesting.topEdgeTolerance + 1
        )

        #expect(!NotchHoverHitTesting.containsVisible(pointInRetainedBandOnly, in: frame))
        #expect(NotchHoverHitTesting.contains(pointInRetainedBandOnly, in: frame))
    }

    @Test("Hover retention includes the top edge just outside the window")
    func retainedFrameIncludesTopEdge() {
        let frame = NSRect(x: 100, y: 900, width: 260, height: 28)
        let pointAtTopEdge = NSPoint(x: frame.midX, y: frame.maxY + 1)

        #expect(!frame.contains(pointAtTopEdge))
        #expect(NotchHoverHitTesting.contains(pointAtTopEdge, in: frame))
    }

    @Test("Hover retention does not keep distant pointer positions")
    func retainedFrameExcludesDistantPoints() {
        let frame = NSRect(x: 100, y: 900, width: 260, height: 28)
        let distantPoint = NSPoint(x: frame.maxX + 80, y: frame.maxY + 80)

        #expect(!NotchHoverHitTesting.contains(distantPoint, in: frame))
    }

    @Test("Hover retention does not extend past the configured edge band")
    func retainedFrameStaysNarrow() {
        let frame = NSRect(x: 100, y: 900, width: 260, height: 28)
        let justPastTopBand = NSPoint(
            x: frame.midX,
            y: frame.maxY + NotchHoverHitTesting.verticalOutset + 1
        )

        #expect(!NotchHoverHitTesting.contains(justPastTopBand, in: frame))
    }
}
