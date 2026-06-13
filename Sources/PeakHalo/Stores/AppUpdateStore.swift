import AppKit
import Foundation

@MainActor
final class AppUpdateStore: ObservableObject {
    static let shared = AppUpdateStore()

    private init() {}

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    var isOnlineUpdateConfigured: Bool {
        SparkleUpdateService.shared.isConfigured
    }

    var feedURLDescription: String {
        SparkleUpdateService.shared.feedURL?.absoluteString
            ?? String(localized: "No online update feed is configured for this build.")
    }

    func checkForUpdates() {
        SparkleUpdateService.shared.checkForUpdates()
    }

    func openReleasePage() {
        NSWorkspace.shared.open(AppUpdateService.repositoryURL.appending(path: "releases"))
    }
}
