import AppKit
import Combine
import SwiftUI

@MainActor
final class AppWindowPresenter {
    static let shared = AppWindowPresenter()

    private let languageStore = AppLanguageStore.shared
    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        languageStore.$language
            .sink { [weak self] language in
                self?.refreshSettingsWindow(language: language)
            }
            .store(in: &cancellables)
    }

    func showSettingsWindow() {
        NotchWindowManager.shared.close(animated: false)

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
        window.title = languageStore.localizedString("PeakHalo Settings")
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

    private func refreshSettingsWindow(language: AppLanguage? = nil) {
        guard let window = settingsWindowController?.window else { return }

        window.title = AppLocalization.localizedString(
            "PeakHalo Settings",
            language: language ?? languageStore.language
        )
        window.contentView = NSHostingView(rootView: SettingsWindowView())
    }
}
