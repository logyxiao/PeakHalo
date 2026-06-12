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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        SystemMetricsService.shared.start()
        NotchWindowManager.shared.show(metricsService: SystemMetricsService.shared)
        MenuBarStatusItemController.shared.start()

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
}
