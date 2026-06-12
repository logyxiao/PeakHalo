import AppKit

@MainActor
final class MenuBarStatusItemController: NSObject {
    static let shared = MenuBarStatusItemController()

    private let preferences = DisplayPreferencesStore.shared
    private var statusItem: NSStatusItem?

    private override init() {
        super.init()
    }

    func start() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: String(localized: "PeakHalo"))
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = String(localized: "PeakHalo")
        statusItem = item
    }

    func stop() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }

        switch preferences.panelActivationMode {
        case .menuBarIcon:
            NotchWindowManager.shared.toggle(fromMenuBarAnchor: statusItemAnchorRect())
        case .notchHover:
            showMenu()
        }
    }

    private func showMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        if preferences.panelActivationMode == .menuBarIcon {
            NotchWindowManager.shared.close(animated: false)
        }

        let menu = NSMenu()
        if preferences.panelActivationMode == .menuBarIcon {
            menu.addItem(withTitle: String(localized: "Toggle Panel"), action: #selector(togglePanel), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: String(localized: "Open Notch"), action: #selector(openPanel), keyEquivalent: "")
            menu.addItem(withTitle: String(localized: "Collapse"), action: #selector(closePanel), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Settings"), action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit PeakHalo"), action: #selector(quit), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func togglePanel() {
        NotchWindowManager.shared.toggle(fromMenuBarAnchor: statusItemAnchorRect())
    }

    @objc
    private func openPanel() {
        NotchWindowManager.shared.open(fromMenuBarAnchor: statusItemAnchorRect())
    }

    @objc
    private func closePanel() {
        NotchWindowManager.shared.close()
    }

    @objc
    private func showSettings() {
        if preferences.panelActivationMode == .menuBarIcon {
            NotchWindowManager.shared.close(animated: false)
        }
        AppWindowPresenter.shared.showSettingsWindow()
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func statusItemAnchorRect() -> NSRect? {
        guard let button = statusItem?.button,
              let window = button.window else {
            return nil
        }

        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}
