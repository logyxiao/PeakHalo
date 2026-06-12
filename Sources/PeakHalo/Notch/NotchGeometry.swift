import AppKit
import CoreGraphics

enum NotchGeometry {
    static func windowSize(
        for screen: NSScreen,
        state: NotchState,
        style: NotchAppearanceStyle
    ) -> CGSize {
        switch state {
        case .closed:
            return closedSize(for: screen, style: style)
        case .open:
            return expandedSize(for: screen, style: style)
        }
    }

    static func windowFrame(
        size: CGSize,
        on screen: NSScreen,
        style: NotchAppearanceStyle
    ) -> NSRect {
        let topGap = style == .dynamicIsland ? CGFloat(8) : CGFloat(0)
        let x = screen.frame.midX - (size.width / 2)
        let y = screen.frame.maxY - size.height - topGap

        return NSRect(
            x: x,
            y: y,
            width: size.width,
            height: size.height
        )
    }

    private static func closedSize(for screen: NSScreen, style: NotchAppearanceStyle) -> CGSize {
        let menuBarHeight = inferredMenuBarHeight(for: screen)
        let baseHeight = min(max(menuBarHeight, 24), 30)
        let height: CGFloat

        if style == .standardNotch, screen.safeAreaInsets.top > 0 {
            height = min(max(screen.safeAreaInsets.top, baseHeight), 32)
        } else {
            height = style == .dynamicIsland ? min(max(baseHeight, 26), 30) : baseHeight
        }

        let realNotchWidth = physicalNotchWidth(for: screen)
        let width = min(max(realNotchWidth + 72, 272), max(screen.frame.width - 48, 220))
        return CGSize(width: width, height: height)
    }

    private static func expandedSize(for screen: NSScreen, style: NotchAppearanceStyle) -> CGSize {
        let closed = closedSize(for: screen, style: style)
        let width = min(max(closed.width + 330, 620), max(screen.frame.width - 56, 340))
        return CGSize(width: width, height: 326)
    }

    private static func inferredMenuBarHeight(for screen: NSScreen) -> CGFloat {
        let height = screen.frame.maxY - screen.visibleFrame.maxY
        guard height.isFinite, height > 0 else { return 28 }
        return height
    }

    private static func physicalNotchWidth(for screen: NSScreen) -> CGFloat {
        guard screen.safeAreaInsets.top > 0,
              let leftWidth = screen.auxiliaryTopLeftArea?.width,
              let rightWidth = screen.auxiliaryTopRightArea?.width else {
            return 200
        }

        return max(0, screen.frame.width - leftWidth - rightWidth + 4)
    }
}
