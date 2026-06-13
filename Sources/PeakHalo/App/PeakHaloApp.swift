import AppKit
import SwiftUI

@main
struct PeakHaloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsWindowView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum LaunchPresentationDefaults {
        static let didShowInitialSettingsWindow = "app.didShowInitialSettingsWindow"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        SystemMetricsService.shared.start()
        NotchWindowManager.shared.show(metricsService: SystemMetricsService.shared)
        MenuBarStatusItemController.shared.start()
        presentInitialSettingsWindowIfNeeded()

        Task { @MainActor in
            DisplayControlController.shared.refreshIfNeeded()
            AudioControlStore.shared.refreshIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MenuBarStatusItemController.shared.stop()
        NotchWindowManager.shared.hide()
        AudioControlStore.shared.shutdown()
        SystemMetricsService.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }

        AppWindowPresenter.shared.showSettingsWindow()
        return true
    }

    private func presentInitialSettingsWindowIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: LaunchPresentationDefaults.didShowInitialSettingsWindow) else {
            return
        }

        defaults.set(true, forKey: LaunchPresentationDefaults.didShowInitialSettingsWindow)
        Task { @MainActor in
            AppWindowPresenter.shared.showSettingsWindow()
        }
    }
}
