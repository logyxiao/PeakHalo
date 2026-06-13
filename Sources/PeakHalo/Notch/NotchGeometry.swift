import AppKit
import CoreGraphics

struct NotchDisplayLayout: Equatable {
    static let none = NotchDisplayLayout(
        hasPhysicalNotch: false,
        physicalNotchWidth: 0,
        centerAvoidanceWidth: 0
    )

    static let closedSideContentWidth = CGFloat(168)
    private static let centerAvoidancePadding = CGFloat(24)

    let hasPhysicalNotch: Bool
    let physicalNotchWidth: CGFloat
    let centerAvoidanceWidth: CGFloat

    init(screen: NSScreen) {
        let width = Self.physicalNotchWidth(for: screen)

        if screen.safeAreaInsets.top > 0, width > 0 {
            hasPhysicalNotch = true
            physicalNotchWidth = width
            centerAvoidanceWidth = width + Self.centerAvoidancePadding
        } else {
            hasPhysicalNotch = false
            physicalNotchWidth = 0
            centerAvoidanceWidth = 0
        }
    }

    private init(
        hasPhysicalNotch: Bool,
        physicalNotchWidth: CGFloat,
        centerAvoidanceWidth: CGFloat
    ) {
        self.hasPhysicalNotch = hasPhysicalNotch
        self.physicalNotchWidth = physicalNotchWidth
        self.centerAvoidanceWidth = centerAvoidanceWidth
    }

    private static func physicalNotchWidth(for screen: NSScreen) -> CGFloat {
        guard screen.safeAreaInsets.top > 0 else { return 0 }

        if let leftWidth = screen.auxiliaryTopLeftArea?.width,
           let rightWidth = screen.auxiliaryTopRightArea?.width {
            let width = screen.frame.width - leftWidth - rightWidth + 4
            if width.isFinite, width > 0 {
                return width
            }
        }

        return 200
    }
}

enum NotchGeometry {
    private static let expandedMinimumWidth = CGFloat(620)
    private static let expandedHorizontalGrowth = CGFloat(260)
    private static let expandedScreenHorizontalPadding = CGFloat(56)
    private static let expandedMinimumScreenWidth = CGFloat(340)

    static func displayLayout(for screen: NSScreen) -> NotchDisplayLayout {
        NotchDisplayLayout(screen: screen)
    }

    static func windowSize(
        for screen: NSScreen,
        state: NotchState,
        style: NotchAppearanceStyle
    ) -> CGSize {
        let layout = displayLayout(for: screen)

        switch state {
        case .closed:
            return closedSize(for: screen, style: style, layout: layout)
        case .open:
            return expandedSize(for: screen, style: style, layout: layout)
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

    static func menuBarPanelFrame(
        size: CGSize,
        anchorRect: NSRect,
        on screen: NSScreen
    ) -> NSRect {
        let horizontalInset = CGFloat(12)
        let verticalGap = CGFloat(8)
        let usableFrame = screen.visibleFrame
        let width = min(size.width, max(usableFrame.width - horizontalInset * 2, 320))
        let height = min(size.height, max(usableFrame.height - verticalGap * 2, 220))
        let minX = usableFrame.minX + horizontalInset
        let maxX = usableFrame.maxX - horizontalInset - width
        let proposedX = anchorRect.midX - width / 2
        let x = clamp(proposedX, min: minX, max: maxX)
        let minY = usableFrame.minY + verticalGap
        let maxY = usableFrame.maxY - verticalGap - height
        let proposedY = anchorRect.minY - verticalGap - height
        let y = clamp(proposedY, min: minY, max: maxY)

        return NSRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    private static func closedSize(
        for screen: NSScreen,
        style: NotchAppearanceStyle,
        layout: NotchDisplayLayout
    ) -> CGSize {
        let baseSize = baseClosedSize(for: screen, style: style, layout: layout)

        guard layout.hasPhysicalNotch else { return baseSize }

        let minimumReadableWidth = layout.centerAvoidanceWidth
            + NotchDisplayLayout.closedSideContentWidth * 2
            + 24
        let width = min(
            max(baseSize.width, minimumReadableWidth),
            max(screen.frame.width - 48, 220)
        )

        return CGSize(width: width, height: baseSize.height)
    }

    private static func baseClosedSize(
        for screen: NSScreen,
        style: NotchAppearanceStyle,
        layout: NotchDisplayLayout
    ) -> CGSize {
        let menuBarHeight = inferredMenuBarHeight(for: screen)
        let baseHeight = min(max(menuBarHeight, 24), 30)
        let height: CGFloat

        if style == .standardNotch, screen.safeAreaInsets.top > 0 {
            height = min(max(screen.safeAreaInsets.top, baseHeight), 32)
        } else {
            height = style == .dynamicIsland ? min(max(baseHeight, 26), 30) : baseHeight
        }

        let realNotchWidth = layout.hasPhysicalNotch ? layout.physicalNotchWidth : 200
        let width = min(max(realNotchWidth + 72, 272), max(screen.frame.width - 48, 220))
        return CGSize(width: width, height: height)
    }

    private static func expandedSize(
        for screen: NSScreen,
        style: NotchAppearanceStyle,
        layout: NotchDisplayLayout
    ) -> CGSize {
        let closed = closedSize(for: screen, style: style, layout: layout)
        let width = expandedWidth(closedWidth: closed.width, screenWidth: screen.frame.width)
        return CGSize(width: width, height: 326)
    }

    static func expandedWidth(closedWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        let targetWidth = max(closedWidth + expandedHorizontalGrowth, expandedMinimumWidth)
        let screenLimit = max(screenWidth - expandedScreenHorizontalPadding, expandedMinimumScreenWidth)
        return min(targetWidth, screenLimit)
    }

    private static func inferredMenuBarHeight(for screen: NSScreen) -> CGFloat {
        let height = screen.frame.maxY - screen.visibleFrame.maxY
        guard height.isFinite, height > 0 else { return 28 }
        return height
    }

    private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else { return minimum }
        return min(max(value, minimum), maximum)
    }
}
