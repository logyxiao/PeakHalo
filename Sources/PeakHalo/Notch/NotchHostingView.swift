import AppKit
import SwiftUI

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var isPointerInside = false

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
        setPointerInside(true)
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if self.window?.frame.contains(NSEvent.mouseLocation) == true {
                self.setPointerInside(true)
            } else {
                self.setPointerInside(false)
            }
        }
    }

    private func reconcilePointerPosition() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.setPointerInside(window.frame.contains(NSEvent.mouseLocation))
        }
    }

    private func setPointerInside(_ isInside: Bool) {
        guard isPointerInside != isInside else { return }

        isPointerInside = isInside
        onHoverChange?(isInside)
    }
}
