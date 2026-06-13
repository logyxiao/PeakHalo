import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .system:
            "Follow System"
        case .english:
            "English"
        case .simplifiedChinese:
            "Simplified Chinese"
        }
    }

    var explicitLocalizationIdentifier: String? {
        switch self {
        case .system:
            nil
        case .english:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        }
    }
}

enum AppLocalization {
    static let defaultLocalizationIdentifier = "en"
    static let supportedLocalizationIdentifiers = ["en", "zh-Hans"]

    static func locale(
        for language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Locale {
        Locale(
            identifier: resolvedLocalizationIdentifier(
                for: language,
                preferredLanguages: preferredLanguages
            )
        )
    }

    static func resolvedLocalizationIdentifier(
        for language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        if let identifier = language.explicitLocalizationIdentifier {
            return identifier
        }

        return Bundle.preferredLocalizations(
            from: supportedLocalizationIdentifiers,
            forPreferences: preferredLanguages
        ).first ?? defaultLocalizationIdentifier
    }

    static func localizedString(
        _ key: String,
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages,
        searchDirectories: [URL]? = nil
    ) -> String {
        let identifier = resolvedLocalizationIdentifier(
            for: language,
            preferredLanguages: preferredLanguages
        )

        let directories = searchDirectories ?? localizationSearchDirectories()
        guard let bundle = bundle(forLocalizationIdentifier: identifier, searchDirectories: directories) else {
            return fallbackLocalizedString(key, searchDirectories: directories)
        }

        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard value != key else {
            return fallbackLocalizedString(key, searchDirectories: directories)
        }

        return value
    }

    static func bundle(
        forLocalizationIdentifier identifier: String,
        searchDirectories: [URL] = localizationSearchDirectories()
    ) -> Bundle? {
        let candidates = [identifier, identifier.lowercased()]

        for directory in searchDirectories {
            for candidate in candidates {
                let directLocalizationURL = directory.appendingPathComponent(
                    "\(candidate).lproj",
                    isDirectory: true
                )
                if let bundle = Bundle(url: directLocalizationURL) {
                    return bundle
                }

                let moduleLocalizationURL = directory
                    .appendingPathComponent("PeakHalo_PeakHalo.bundle", isDirectory: true)
                    .appendingPathComponent("\(candidate).lproj", isDirectory: true)
                if let bundle = Bundle(url: moduleLocalizationURL) {
                    return bundle
                }
            }
        }

        return nil
    }

    static func localizationSearchDirectories(
        mainBundle: Bundle = .main,
        executablePath: String? = CommandLine.arguments.first
    ) -> [URL] {
        var urls: [URL] = []

        if let resourceURL = mainBundle.resourceURL {
            urls.append(resourceURL)
        }

        urls.append(mainBundle.bundleURL)
        urls.append(contentsOf: ancestorDirectories(from: mainBundle.bundleURL))

        for bundle in Bundle.allBundles + Bundle.allFrameworks {
            if let resourceURL = bundle.resourceURL {
                urls.append(resourceURL)
            }
            urls.append(contentsOf: ancestorDirectories(from: bundle.bundleURL))
        }

        if let executablePath {
            urls.append(
                contentsOf: ancestorDirectories(
                    from: URL(fileURLWithPath: executablePath).deletingLastPathComponent()
                )
            )
        }

        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }

    private static func ancestorDirectories(from url: URL, limit: Int = 5) -> [URL] {
        var directories: [URL] = []
        var current = url

        for _ in 0..<limit {
            directories.append(current)
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }

        return directories
    }

    private static func fallbackLocalizedString(_ key: String, searchDirectories: [URL]) -> String {
        guard let bundle = bundle(
            forLocalizationIdentifier: defaultLocalizationIdentifier,
            searchDirectories: searchDirectories
        ) else {
            return key
        }

        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()

    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }

            defaults.set(language.rawValue, forKey: Keys.language)
            applyAppleLanguagesPreference()
        }
    }

    var locale: Locale {
        AppLocalization.locale(for: language)
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let language = "app.language"
        static let appleLanguages = "AppleLanguages"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawLanguage = defaults.string(forKey: Keys.language),
           let storedLanguage = AppLanguage(rawValue: rawLanguage) {
            language = storedLanguage
        } else {
            language = .system
        }

        applyAppleLanguagesPreference()
    }

    func localizedString(_ key: String) -> String {
        AppLocalization.localizedString(key, language: language)
    }

    private func applyAppleLanguagesPreference() {
        if let identifier = language.explicitLocalizationIdentifier {
            defaults.set([identifier], forKey: Keys.appleLanguages)
        } else {
            defaults.removeObject(forKey: Keys.appleLanguages)
        }
    }
}
