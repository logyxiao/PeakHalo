import AppKit

struct NotchPanelPresentationState: Equatable {
    private(set) var isMenuBarPanelVisible = false
    private(set) var isMenuBarPanelClosing = false
    private(set) var menuBarAnchorRect: NSRect?

    var shouldKeepMenuBarPanelContext: Bool {
        isMenuBarPanelVisible || isMenuBarPanelClosing
    }

    var shouldRemoveInactiveMenuBarPanelContext: Bool {
        !isMenuBarPanelVisible && !isMenuBarPanelClosing
    }

    mutating func show(anchorRect: NSRect?) {
        if let anchorRect {
            menuBarAnchorRect = anchorRect
        }
        isMenuBarPanelVisible = true
        isMenuBarPanelClosing = false
    }

    mutating func beginHide(animated: Bool) -> Bool {
        guard isMenuBarPanelVisible || isMenuBarPanelClosing else {
            clear()
            return false
        }

        isMenuBarPanelVisible = false
        isMenuBarPanelClosing = animated
        return true
    }

    mutating func completeHide() {
        guard !isMenuBarPanelVisible else { return }
        isMenuBarPanelClosing = false
        menuBarAnchorRect = nil
    }

    mutating func resetForNotchHoverMode() {
        clear()
    }

    mutating func clear() {
        isMenuBarPanelVisible = false
        isMenuBarPanelClosing = false
        menuBarAnchorRect = nil
    }
}
