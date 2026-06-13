import AppKit

enum NotchPanelPlacement {
    static func screen(
        for anchorRect: NSRect?,
        screens: [NSScreen] = NSScreen.screens,
        fallback: NSScreen?
    ) -> NSScreen? {
        guard let anchorRect else { return fallback }

        let anchorCenter = CGPoint(x: anchorRect.midX, y: anchorRect.midY)
        return screens.first { screen in
            screen.frame.contains(anchorCenter)
        } ?? fallback
    }

    static func fallbackMenuBarAnchorRect(on screen: NSScreen) -> NSRect {
        fallbackMenuBarAnchorRect(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    static func fallbackMenuBarAnchorRect(screenFrame: NSRect, visibleFrame: NSRect) -> NSRect {
        let menuBarHeight = max(screenFrame.maxY - visibleFrame.maxY, 24)
        let size = CGSize(width: 28, height: menuBarHeight)
        return NSRect(
            x: visibleFrame.maxX - size.width - 16,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
