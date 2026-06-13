import AppKit
import Combine

@MainActor
final class MenuBarStatusItemController: NSObject {
    static let shared = MenuBarStatusItemController()

    private let preferences = DisplayPreferencesStore.shared
    private let languageStore = AppLanguageStore.shared
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private static let statusItemLength: CGFloat = NSStatusItem.squareLength
    private static let statusIconSize = NSSize(width: 18, height: 18)

    private override init() {
        super.init()
        languageStore.$language
            .sink { [weak self] language in
                self?.refreshStatusItemLocalization(language: language)
            }
            .store(in: &cancellables)
    }

    func start() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: Self.statusItemLength)
        item.isVisible = true
        item.button?.image = Self.makeStatusBarIcon()
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.imagePosition = .imageOnly
        item.button?.title = ""
        item.button?.isBordered = false
        item.button?.setAccessibilityLabel(languageStore.localizedString("PeakHalo"))
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = languageStore.localizedString("PeakHalo")
        statusItem = item
        refreshStatusItemLocalization()
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
        NotchWindowManager.shared.close(animated: false)

        let menu = NSMenu()
        menu.addItem(
            withTitle: languageStore.localizedString("Settings"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        menu.addItem(
            withTitle: languageStore.localizedString("Quit PeakHalo"),
            action: #selector(quit),
            keyEquivalent: "q"
        )

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func refreshStatusItemLocalization(language: AppLanguage? = nil) {
        guard let button = statusItem?.button else { return }
        let title = AppLocalization.localizedString(
            "PeakHalo",
            language: language ?? languageStore.language
        )
        button.setAccessibilityLabel(title)
        button.toolTip = title
    }

    @objc
    private func showSettings() {
        NotchWindowManager.shared.close(animated: false)
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

    private static func makeStatusBarIcon() -> NSImage {
        if let symbolImage = NSImage(
            systemSymbolName: "waveform.path.ecg.circle.fill",
            accessibilityDescription: AppLocalization.localizedString("PeakHalo", language: .system)
        ) {
            symbolImage.isTemplate = true
            return symbolImage
        }

        return makeLogoStatusBarIcon()
    }

    private static func makeLogoStatusBarIcon() -> NSImage {
        let size = statusIconSize
        let image = NSImage(size: size, flipped: false) { rect in
            let strokeColor = NSColor.black.withAlphaComponent(0.92)
            strokeColor.setStroke()
            strokeColor.setFill()

            let haloPath = NSBezierPath()
            haloPath.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY - 0.3),
                radius: 5.15,
                startAngle: 36,
                endAngle: 326
            )
            haloPath.lineWidth = 1.7
            haloPath.lineCapStyle = .round
            haloPath.stroke()

            let notchRect = NSRect(x: rect.midX - 2.2, y: rect.maxY - 4.9, width: 4.4, height: 1.5)
            let notchPath = NSBezierPath(roundedRect: notchRect, xRadius: 0.75, yRadius: 0.75)
            notchPath.fill()

            let pulsePath = NSBezierPath()
            pulsePath.lineWidth = 1.45
            pulsePath.lineCapStyle = .round
            pulsePath.lineJoinStyle = .round
            pulsePath.move(to: NSPoint(x: rect.midX - 2.6, y: rect.midY - 0.8))
            pulsePath.line(to: NSPoint(x: rect.midX - 1.0, y: rect.midY - 0.8))
            pulsePath.line(to: NSPoint(x: rect.midX - 0.1, y: rect.midY + 0.9))
            pulsePath.line(to: NSPoint(x: rect.midX + 1.0, y: rect.midY - 1.8))
            pulsePath.line(to: NSPoint(x: rect.midX + 2.2, y: rect.midY - 0.2))
            pulsePath.line(to: NSPoint(x: rect.midX + 3.4, y: rect.midY - 0.2))
            pulsePath.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppLocalization.localizedString("PeakHalo", language: .system)
        return image
    }
}
