import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .system:
            "Follow System"
        case .english:
            "English"
        case .simplifiedChinese:
            "Simplified Chinese"
        }
    }

    var localizedName: LocalizedStringKey {
        LocalizedStringKey(localizationKey)
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

struct LocalizedMessage: Equatable {
    indirect enum Argument: Equatable {
        case string(String)
        case int(Int)
        case double(Double)
        case message(LocalizedMessage)

        func formatArgument(
            language: AppLanguage,
            preferredLanguages: [String] = Locale.preferredLanguages
        ) -> CVarArg {
            switch self {
            case .string(let value):
                value
            case .int(let value):
                value
            case .double(let value):
                value
            case .message(let message):
                message.resolved(language: language, preferredLanguages: preferredLanguages)
            }
        }
    }

    let key: String
    let arguments: [Argument]

    init(_ key: String, arguments: [Argument] = []) {
        self.key = key
        self.arguments = arguments
    }

    static func string(_ key: String) -> LocalizedMessage {
        LocalizedMessage(key)
    }

    func resolved(
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        AppLocalization.localizedString(
            key,
            language: language,
            preferredLanguages: preferredLanguages,
            arguments: arguments
        )
    }
}

enum AppLocalization {
    static let defaultLocalizationIdentifier = "en"
    static let supportedLocalizationIdentifiers = ["en", "zh-Hans"]
    private static let cacheLock = NSLock()
    private static var cachedDefaultSearchDirectories: [URL]?
    private static var cachedBundlesByKey: [String: [Bundle]] = [:]
    private static var cachedLocalizationFileURLsByKey: [String: [URL]] = [:]
    private static var cachedLocalizedStringTables: [String: [String: String]] = [:]
    private static var cachedMergedLocalizedStringTables: [String: [String: String]] = [:]
    private static var missingLocalizedStringTables = Set<String>()

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

        let usesDefaultSearchDirectories = searchDirectories == nil
        let directories = searchDirectories ?? localizationSearchDirectories()
        if let value = localizedStringFromMergedTable(
            key,
            localizationIdentifier: identifier,
            searchDirectories: directories,
            usesDefaultSearchDirectories: usesDefaultSearchDirectories
        ) {
            return value
        }

        for bundle in bundles(
            forLocalizationIdentifier: identifier,
            searchDirectories: directories,
            usesDefaultSearchDirectories: usesDefaultSearchDirectories
        ) {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if !value.isEmpty, value != key {
                return value
            }
        }

        return fallbackLocalizedString(
            key,
            searchDirectories: directories,
            usesDefaultSearchDirectories: usesDefaultSearchDirectories
        )
    }

    static func localizedString(
        _ key: String,
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages,
        searchDirectories: [URL]? = nil,
        arguments: [LocalizedMessage.Argument]
    ) -> String {
        let format = localizedString(
            key,
            language: language,
            preferredLanguages: preferredLanguages,
            searchDirectories: searchDirectories
        )
        guard !arguments.isEmpty else { return format }

        return String(
            format: format,
            locale: locale(for: language, preferredLanguages: preferredLanguages),
            arguments: arguments.map {
                $0.formatArgument(language: language, preferredLanguages: preferredLanguages)
            }
        )
    }

    static func prewarm() {
        let directories = localizationSearchDirectories()
        for identifier in supportedLocalizationIdentifiers {
            _ = mergedLocalizedStringTable(
                forLocalizationIdentifier: identifier,
                searchDirectories: directories,
                usesDefaultSearchDirectories: true
            )
        }
    }

    static func bundle(
        forLocalizationIdentifier identifier: String,
        searchDirectories: [URL] = localizationSearchDirectories()
    ) -> Bundle? {
        bundles(
            forLocalizationIdentifier: identifier,
            searchDirectories: searchDirectories
        ).first
    }

    private static func bundles(
        forLocalizationIdentifier identifier: String,
        searchDirectories: [URL] = localizationSearchDirectories(),
        usesDefaultSearchDirectories: Bool = false
    ) -> [Bundle] {
        let key = localizationCacheKey(
            identifier: identifier,
            searchDirectories: searchDirectories,
            usesDefaultSearchDirectories: usesDefaultSearchDirectories
        )
        if let bundles = cachedBundles(for: key) {
            return bundles
        }

        let candidates = [identifier, identifier.lowercased()]
        var bundles: [Bundle] = []
        var seen = Set<String>()

        for directory in searchDirectories {
            for candidate in candidates {
                let directLocalizationURL = directory.appendingPathComponent(
                    "\(candidate).lproj",
                    isDirectory: true
                )
                if let bundle = Bundle(url: directLocalizationURL) {
                    let path = directLocalizationURL.standardizedFileURL.path
                    if seen.insert(path).inserted {
                        bundles.append(bundle)
                    }
                }

                let moduleLocalizationURL = directory
                    .appendingPathComponent("PeakHalo_PeakHalo.bundle", isDirectory: true)
                    .appendingPathComponent("\(candidate).lproj", isDirectory: true)
                if let bundle = Bundle(url: moduleLocalizationURL) {
                    let path = moduleLocalizationURL.standardizedFileURL.path
                    if seen.insert(path).inserted {
                        bundles.append(bundle)
                    }
                }
            }
        }

        setCachedBundles(bundles, for: key)
        return bundles
    }

    static func localizationSearchDirectories(
        mainBundle: Bundle = .main,
        executablePath: String? = CommandLine.arguments.first
    ) -> [URL] {
        let canUseDefaultCache = mainBundle.bundleURL == Bundle.main.bundleURL
            && executablePath == CommandLine.arguments.first
        if canUseDefaultCache, let directories = cachedSearchDirectories() {
            return directories
        }

        var urls: [URL] = []

        if let resourceURL = mainBundle.resourceURL {
            urls.append(resourceURL)
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        urls.append(currentDirectory.appendingPathComponent("Sources/PeakHalo/Resources", isDirectory: true))
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
        let directories = urls.filter { url in
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }

        if canUseDefaultCache {
            setCachedSearchDirectories(directories)
        }

        return directories
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

    private static func fallbackLocalizedString(
        _ key: String,
        searchDirectories: [URL],
        usesDefaultSearchDirectories: Bool = false
    ) -> String {
        if let value = localizedStringFromMergedTable(
            key,
            localizationIdentifier: defaultLocalizationIdentifier,
            searchDirectories: searchDirectories,
            usesDefaultSearchDirectories: usesDefaultSearchDirectories
        ) {
            return value
        }

        for bundle in bundles(
            forLocalizationIdentifier: defaultLocalizationIdentifier,
            searchDirectories: searchDirectories,
            usesDefaultSearchDirectories: usesDefaultSearchDirectories
        ) {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if !value.isEmpty, value != key {
                return value
            }
        }

        return key
    }

    private static func localizedStringFromMergedTable(
        _ key: String,
        localizationIdentifier identifier: String,
        searchDirectories: [URL],
        usesDefaultSearchDirectories: Bool
    ) -> String? {
        let table = mergedLocalizedStringTable(
            forLocalizationIdentifier: identifier,
            searchDirectories: searchDirectories,
            usesDefaultSearchDirectories: usesDefaultSearchDirectories
        )
        guard let value = table[key], !value.isEmpty, value != key else {
            return nil
        }

        return value
    }

    private static func mergedLocalizedStringTable(
        forLocalizationIdentifier identifier: String,
        searchDirectories: [URL],
        usesDefaultSearchDirectories: Bool
    ) -> [String: String] {
        let key = localizationCacheKey(
            identifier: identifier,
            searchDirectories: searchDirectories,
            usesDefaultSearchDirectories: usesDefaultSearchDirectories
        )
        if let table = cachedMergedLocalizedStringTable(for: key) {
            return table
        }

        var merged: [String: String] = [:]
        for url in localizationFileURLs(
            forLocalizationIdentifier: identifier,
            searchDirectories: searchDirectories,
            cacheKey: key
        ) {
            guard let strings = localizedStrings(at: url) else { continue }
            for (stringKey, value) in strings where !value.isEmpty && value != stringKey {
                if merged[stringKey] == nil {
                    merged[stringKey] = value
                }
            }
        }

        setCachedMergedLocalizedStringTable(merged, for: key)
        return merged
    }

    private static func localizationFileURLs(
        forLocalizationIdentifier identifier: String,
        searchDirectories: [URL],
        cacheKey: String? = nil
    ) -> [URL] {
        let key = cacheKey ?? localizationCacheKey(identifier: identifier, searchDirectories: searchDirectories)
        if let urls = cachedLocalizationFileURLs(for: key) {
            return urls
        }

        let candidates = [identifier, identifier.lowercased()]
        var urls: [URL] = []
        var seen = Set<String>()

        for directory in searchDirectories {
            for candidate in candidates {
                let directURL = directory
                    .appendingPathComponent("\(candidate).lproj", isDirectory: true)
                    .appendingPathComponent("Localizable.strings")
                if FileManager.default.fileExists(atPath: directURL.path),
                   seen.insert(directURL.standardizedFileURL.path).inserted {
                    urls.append(directURL)
                }

                let moduleURL = directory
                    .appendingPathComponent("PeakHalo_PeakHalo.bundle", isDirectory: true)
                    .appendingPathComponent("\(candidate).lproj", isDirectory: true)
                    .appendingPathComponent("Localizable.strings")
                if FileManager.default.fileExists(atPath: moduleURL.path),
                   seen.insert(moduleURL.standardizedFileURL.path).inserted {
                    urls.append(moduleURL)
                }
            }
        }

        setCachedLocalizationFileURLs(urls, for: key)
        return urls
    }

    private static func localizedStrings(at url: URL) -> [String: String]? {
        let path = url.standardizedFileURL.path
        if let cached = cachedLocalizedStringTable(for: path) {
            return cached
        }

        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let strings = plist as? [String: String] else {
            setMissingLocalizedStringTable(for: path)
            return nil
        }

        setCachedLocalizedStringTable(strings, for: path)
        return strings
    }

    private static func localizationCacheKey(
        identifier: String,
        searchDirectories: [URL],
        usesDefaultSearchDirectories: Bool = false
    ) -> String {
        if usesDefaultSearchDirectories {
            return "\(identifier)|default"
        }

        return ([identifier] + searchDirectories.map { $0.standardizedFileURL.path }).joined(separator: "|")
    }

    private static func cachedSearchDirectories() -> [URL]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedDefaultSearchDirectories
    }

    private static func setCachedSearchDirectories(_ directories: [URL]) {
        cacheLock.lock()
        cachedDefaultSearchDirectories = directories
        cacheLock.unlock()
    }

    private static func cachedBundles(for key: String) -> [Bundle]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedBundlesByKey[key]
    }

    private static func setCachedBundles(_ bundles: [Bundle], for key: String) {
        cacheLock.lock()
        cachedBundlesByKey[key] = bundles
        cacheLock.unlock()
    }

    private static func cachedLocalizationFileURLs(for key: String) -> [URL]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedLocalizationFileURLsByKey[key]
    }

    private static func setCachedLocalizationFileURLs(_ urls: [URL], for key: String) {
        cacheLock.lock()
        cachedLocalizationFileURLsByKey[key] = urls
        cacheLock.unlock()
    }

    private static func cachedLocalizedStringTable(for path: String) -> [String: String]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard !missingLocalizedStringTables.contains(path) else { return nil }
        return cachedLocalizedStringTables[path]
    }

    private static func setCachedLocalizedStringTable(_ table: [String: String], for path: String) {
        cacheLock.lock()
        cachedLocalizedStringTables[path] = table
        missingLocalizedStringTables.remove(path)
        cacheLock.unlock()
    }

    private static func cachedMergedLocalizedStringTable(for key: String) -> [String: String]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedMergedLocalizedStringTables[key]
    }

    private static func setCachedMergedLocalizedStringTable(_ table: [String: String], for key: String) {
        cacheLock.lock()
        cachedMergedLocalizedStringTables[key] = table
        cacheLock.unlock()
    }

    private static func setMissingLocalizedStringTable(for path: String) {
        cacheLock.lock()
        missingLocalizedStringTables.insert(path)
        cacheLock.unlock()
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()

    @Published private(set) var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }

            persist(language)
        }
    }

    var locale: Locale {
        AppLocalization.locale(for: language)
    }

    private let defaults: UserDefaults
    private let stableDefaults: UserDefaults?
    private let legacyExecutableDefaults: UserDefaults?

    private enum Keys {
        static let language = "app.language"
        static let legacyAppleLanguages = "AppleLanguages"
        static let stableSuiteName = "com.logyxiao.PeakHalo"
        static let legacyExecutableSuiteName = "PeakHalo"
    }

    private init(
        defaults: UserDefaults = .standard,
        stableDefaults: UserDefaults? = UserDefaults(suiteName: Keys.stableSuiteName),
        legacyExecutableDefaults: UserDefaults? = UserDefaults(suiteName: Keys.legacyExecutableSuiteName)
    ) {
        self.defaults = defaults
        self.stableDefaults = stableDefaults
        self.legacyExecutableDefaults = legacyExecutableDefaults

        language = Self.resolvedStoredLanguage(
            primaryRaw: defaults.string(forKey: Keys.language),
            stableRaw: stableDefaults?.string(forKey: Keys.language),
            legacyRaw: legacyExecutableDefaults?.string(forKey: Keys.language)
        )

        persist(language)
        AppLocalization.prewarm()
    }

    func localizedString(_ key: String) -> String {
        AppLocalization.localizedString(key, language: language)
    }

    func localizedString(_ message: LocalizedMessage) -> String {
        message.resolved(language: language)
    }

    func localizedString(_ key: String, arguments: [LocalizedMessage.Argument]) -> String {
        AppLocalization.localizedString(key, language: language, arguments: arguments)
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else {
            persist(language)
            return
        }
        self.language = language
    }

    nonisolated static func resolvedStoredLanguage(
        primaryRaw: String?,
        stableRaw: String?,
        legacyRaw: String?
    ) -> AppLanguage {
        let storedLanguages = [primaryRaw, stableRaw, legacyRaw]
            .compactMap { rawValue -> AppLanguage? in
                guard let rawValue else { return nil }
                return AppLanguage(rawValue: rawValue)
            }

        if let explicitLanguage = storedLanguages.first(where: { $0 != .system }) {
            return explicitLanguage
        }

        return storedLanguages.first ?? .system
    }

    private func persist(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Keys.language)
        defaults.removeObject(forKey: Keys.legacyAppleLanguages)
        stableDefaults?.set(language.rawValue, forKey: Keys.language)
        stableDefaults?.removeObject(forKey: Keys.legacyAppleLanguages)
        legacyExecutableDefaults?.set(language.rawValue, forKey: Keys.language)
        legacyExecutableDefaults?.removeObject(forKey: Keys.legacyAppleLanguages)
    }
}
