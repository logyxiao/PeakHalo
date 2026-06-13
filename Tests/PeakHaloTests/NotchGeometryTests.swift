import Testing
@testable import PeakHalo

@Suite("Notch geometry")
struct NotchGeometryTests {
    @Test("Expanded width grows from widened closed width")
    func expandedWidthGrowsFromWidenedClosedWidth() {
        let width = NotchGeometry.expandedWidth(closedWidth: 584, screenWidth: 1512)

        #expect(width == 844)
    }

    @Test("Expanded width preserves compact minimum")
    func expandedWidthPreservesCompactMinimum() {
        let width = NotchGeometry.expandedWidth(closedWidth: 272, screenWidth: 1512)

        #expect(width == 620)
    }

    @Test("Expanded width respects screen edge padding")
    func expandedWidthRespectsScreenEdgePadding() {
        let width = NotchGeometry.expandedWidth(closedWidth: 900, screenWidth: 1000)

        #expect(width == 944)
    }
}
