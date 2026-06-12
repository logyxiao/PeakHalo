import AppKit
import SwiftUI

@MainActor
final class AppWindowPresenter {
    static let shared = AppWindowPresenter()

    private var settingsWindowController: NSWindowController?

    private init() {}

    func showSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "PeakHalo Settings")
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("PeakHaloSettingsWindow")
        window.center()
        window.contentView = NSHostingView(rootView: SettingsWindowView())

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
