import AppKit
import Testing
@testable import PeakHalo

@Suite("Notch panel presentation state")
struct NotchPanelPresentationStateTests {
    @Test("Show records anchor and keeps menu bar panel context")
    func showRecordsAnchor() {
        var state = NotchPanelPresentationState()
        let anchor = NSRect(x: 10, y: 20, width: 30, height: 40)

        state.show(anchorRect: anchor)

        #expect(state.isMenuBarPanelVisible)
        #expect(state.isMenuBarPanelClosing == false)
        #expect(state.menuBarAnchorRect == anchor)
        #expect(state.shouldKeepMenuBarPanelContext)
    }

    @Test("Animated hide keeps context until completion")
    func animatedHideKeepsContextUntilCompletion() {
        var state = NotchPanelPresentationState()
        state.show(anchorRect: NSRect(x: 1, y: 2, width: 3, height: 4))

        let didBeginHide = state.beginHide(animated: true)

        #expect(didBeginHide)
        #expect(state.isMenuBarPanelVisible == false)
        #expect(state.isMenuBarPanelClosing)
        #expect(state.shouldKeepMenuBarPanelContext)

        state.completeHide()
        #expect(state.shouldRemoveInactiveMenuBarPanelContext)
        #expect(state.menuBarAnchorRect == nil)
    }

    @Test("Hide with inactive state clears and reports no active hide")
    func inactiveHideClearsState() {
        var state = NotchPanelPresentationState()

        let didBeginHide = state.beginHide(animated: true)

        #expect(didBeginHide == false)
        #expect(state.shouldRemoveInactiveMenuBarPanelContext)
    }
}
