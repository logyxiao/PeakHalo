import AppKit
import SwiftUI

enum NotchHoverHitTesting {
    static let horizontalOutset = CGFloat(14)
    static let verticalOutset = CGFloat(10)
    static let topEdgeTolerance = CGFloat(2)

    static func retainedFrame(for frame: NSRect) -> NSRect {
        frame.insetBy(dx: -horizontalOutset, dy: -verticalOutset)
    }

    static func containsVisible(_ point: NSPoint, in frame: NSRect) -> Bool {
        containsInclusive(
            point,
            in: frame,
            topEdgeTolerance: topEdgeTolerance
        )
    }

    static func contains(_ point: NSPoint, in frame: NSRect) -> Bool {
        containsInclusive(
            point,
            in: retainedFrame(for: frame),
            topEdgeTolerance: 0
        )
    }

    private static func containsInclusive(
        _ point: NSPoint,
        in frame: NSRect,
        topEdgeTolerance: CGFloat
    ) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }

        return point.x >= frame.minX
            && point.x <= frame.maxX
            && point.y >= frame.minY
            && point.y <= frame.maxY + topEdgeTolerance
    }
}

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var hoverReconcileWorkItem: DispatchWorkItem?
    private var isPointerInside = false

    deinit {
        hoverReconcileWorkItem?.cancel()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        hoverTrackingArea = trackingArea
        addTrackingArea(trackingArea)
        reconcilePointerPosition()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reconcilePointerPosition()
    }

    override func mouseEntered(with event: NSEvent) {
        hoverReconcileWorkItem?.cancel()
        hoverReconcileWorkItem = nil
        reconcilePointerPosition()
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reconcilePointerPosition(repeatWhileRetained: true)
        }
    }

    private func reconcilePointerPosition(repeatWhileRetained: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let window = self.window else {
                self.setPointerInside(false)
                self.hoverReconcileWorkItem?.cancel()
                self.hoverReconcileWorkItem = nil
                return
            }

            let mouseLocation = NSEvent.mouseLocation
            let isInsideWindow = NotchHoverHitTesting.containsVisible(mouseLocation, in: window.frame)
            let isRetained = repeatWhileRetained && NotchHoverHitTesting.contains(mouseLocation, in: window.frame)
            self.setPointerInside(isInsideWindow || isRetained)

            if repeatWhileRetained, !isInsideWindow, isRetained {
                self.scheduleRetainedHoverRecheck()
            } else {
                self.hoverReconcileWorkItem?.cancel()
                self.hoverReconcileWorkItem = nil
            }
        }
    }

    private func scheduleRetainedHoverRecheck() {
        hoverReconcileWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.reconcilePointerPosition(repeatWhileRetained: true)
        }
        hoverReconcileWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
    }

    private func setPointerInside(_ isInside: Bool) {
        guard isPointerInside != isInside else { return }

        isPointerInside = isInside
        onHoverChange?(isInside)
    }
}
