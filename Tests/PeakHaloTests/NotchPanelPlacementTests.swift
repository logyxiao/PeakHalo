import AppKit
import Testing
@testable import PeakHalo

@Suite("Notch panel placement")
struct NotchPanelPlacementTests {
    @Test("Fallback menu bar anchor uses visible frame trailing edge")
    func fallbackMenuBarAnchorUsesVisibleFrameTrailingEdge() {
        let anchor = NotchPanelPlacement.fallbackMenuBarAnchorRect(
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 944)
        )

        #expect(anchor.width == 28)
        #expect(anchor.height == 38)
        #expect(anchor.minX == 1468)
        #expect(anchor.minY == 944)
    }

    @Test("Fallback menu bar anchor has minimum height")
    func fallbackMenuBarAnchorHasMinimumHeight() {
        let anchor = NotchPanelPlacement.fallbackMenuBarAnchorRect(
            screenFrame: NSRect(x: 0, y: 0, width: 1000, height: 800),
            visibleFrame: NSRect(x: 0, y: 0, width: 1000, height: 790)
        )

        #expect(anchor.height == 24)
        #expect(anchor.minY == 776)
    }
}
