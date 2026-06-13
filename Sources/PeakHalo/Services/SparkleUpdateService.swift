import AppKit
import Foundation
import ObjectiveC

@MainActor
final class SparkleUpdateService {
    static let shared = SparkleUpdateService()

    let feedURL: URL?
    let publicEdKey: String?

    private var updaterController: NSObject?
    private var didStartUpdater = false

    private init() {
        feedURL = Self.bundleURL(forInfoDictionaryKey: "SUFeedURL")
        publicEdKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    }

    var isConfigured: Bool {
        feedURL != nil && publicEdKey != nil
    }

    var canCheckForUpdates: Bool {
        isConfigured
    }

    func start() {
        guard isConfigured, !didStartUpdater else { return }
        guard let updaterController = makeUpdaterController() else { return }
        self.updaterController = updaterController
        didStartUpdater = true
    }

    func checkForUpdates() {
        guard isConfigured else {
            NSWorkspace.shared.open(AppUpdateService.repositoryURL.appending(path: "releases"))
            return
        }

        start()
        updaterController?.perform(NSSelectorFromString("checkForUpdates:"), with: nil)
    }

    private func makeUpdaterController() -> NSObject? {
        if let updaterController {
            return updaterController
        }

        guard loadSparkleFramework(),
              let controllerClass = NSClassFromString("SPUStandardUpdaterController") as? NSObject.Type else {
            return nil
        }

        let selector = NSSelectorFromString("initWithUpdaterDelegate:userDriverDelegate:")
        guard let instance = class_createInstance(controllerClass, 0) as? NSObject else {
            return nil
        }

        return instance.perform(selector, with: nil, with: nil)?.takeUnretainedValue() as? NSObject
    }

    private func loadSparkleFramework() -> Bool {
        let frameworkURL = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("Sparkle.framework")

        guard let frameworkURL,
              let frameworkBundle = Bundle(url: frameworkURL) else {
            return false
        }

        if frameworkBundle.isLoaded {
            return true
        }

        return frameworkBundle.load()
    }

    private static func bundleURL(forInfoDictionaryKey key: String) -> URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
