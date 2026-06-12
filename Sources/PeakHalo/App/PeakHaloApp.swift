import AppKit
import SwiftUI

@main
struct PeakHaloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var metricsService = SystemMetricsService.shared

    var body: some Scene {
        WindowGroup("PeakHalo", id: "main") {
            ContentView(metricsService: metricsService)
                .frame(minWidth: 420, minHeight: 260)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        SystemMetricsService.shared.start()
        NotchWindowManager.shared.show(metricsService: SystemMetricsService.shared)

        Task { @MainActor in
            DisplayControlController.shared.refreshIfNeeded()
            AudioControlStore.shared.refreshIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotchWindowManager.shared.hide()
        AudioControlStore.shared.shutdown()
        SystemMetricsService.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
