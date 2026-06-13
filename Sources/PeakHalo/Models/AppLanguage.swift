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
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let identifier = resolvedLocalizationIdentifier(
            for: language,
            preferredLanguages: preferredLanguages
        )

        guard let bundle = bundle(forLocalizationIdentifier: identifier) else {
            return fallbackLocalizedString(key)
        }

        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard value != key else {
            return fallbackLocalizedString(key)
        }

        return value
    }

    private static func bundle(forLocalizationIdentifier identifier: String) -> Bundle? {
        let candidates = [identifier, identifier.lowercased()]

        for candidate in candidates {
            if let path = Bundle.module.path(forResource: candidate, ofType: "lproj") {
                return Bundle(path: path)
            }
        }

        return nil
    }

    private static func fallbackLocalizedString(_ key: String) -> String {
        guard let bundle = bundle(forLocalizationIdentifier: defaultLocalizationIdentifier) else {
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
