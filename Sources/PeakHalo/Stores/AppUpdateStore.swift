import AppKit
import Foundation

@MainActor
final class AppUpdateStore: ObservableObject {
    static let shared = AppUpdateStore()

    @Published private(set) var isChecking = false
    @Published private(set) var latestUpdate: AppUpdateInfo?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private var hasChecked = false

    private init() {}

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }

    func checkForUpdatesIfNeeded() async {
        guard !hasChecked else { return }
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard !isChecking else { return }

        isChecking = true
        hasChecked = true
        errorMessage = nil
        statusMessage = String(localized: "Checking for updates...")

        do {
            let info = try await AppUpdateService.checkForUpdates(currentVersion: currentVersion)
            latestUpdate = info
            statusMessage = info.isUpdateAvailable
                ? String.localizedStringWithFormat(
                    String(localized: "Version %@ is available."),
                    info.latestVersion
                )
                : String(localized: "PeakHalo is up to date.")
        } catch {
            latestUpdate = nil
            statusMessage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isChecking = false
    }

    func openDownload() {
        if let assetURL = latestUpdate?.assetURL {
            NSWorkspace.shared.open(assetURL)
            return
        }

        openReleasePage()
    }

    func openReleasePage() {
        NSWorkspace.shared.open(latestUpdate?.releaseURL ?? AppUpdateService.repositoryURL)
    }
}
