import Foundation

struct LocalizedMetricsStrings {
    let language: AppLanguage
    let locale: Locale

    private static let cacheLock = NSLock()
    private static var cachedByLanguage: [String: LocalizedMetricsStrings] = [:]

    private let values: [String: String]
    private let resourceTitles: [ResourceMonitorKind: String]
    private let tabTitles: [NotchMetricsTab: String]
    private let layoutTitles: [MonitorLayoutStyle: String]

    static func cached(
        for language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> LocalizedMetricsStrings {
        let cacheKey = ([language.rawValue] + preferredLanguages).joined(separator: "|")
        cacheLock.lock()
        if let cached = cachedByLanguage[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let strings = LocalizedMetricsStrings(
            language: language,
            preferredLanguages: preferredLanguages
        )

        cacheLock.lock()
        cachedByLanguage[cacheKey] = strings
        cacheLock.unlock()

        return strings
    }

    init(language: AppLanguage, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.language = language
        locale = AppLocalization.locale(for: language, preferredLanguages: preferredLanguages)

        let resolve: (String) -> String = {
            AppLocalization.localizedString(
                $0,
                language: language,
                preferredLanguages: preferredLanguages
            )
        }

        values = Dictionary(
            uniqueKeysWithValues: Self.keys.map { ($0, resolve($0)) }
        )
        resourceTitles = Dictionary(
            uniqueKeysWithValues: ResourceMonitorKind.allCases.map { ($0, resolve($0.titleKey)) }
        )
        tabTitles = Dictionary(
            uniqueKeysWithValues: NotchMetricsTab.allCases.map { ($0, resolve($0.titleKey)) }
        )
        layoutTitles = Dictionary(
            uniqueKeysWithValues: MonitorLayoutStyle.allCases.map { ($0, resolve($0.localizedNameKey)) }
        )
    }

    func text(_ key: String) -> String {
        values[key] ?? key
    }

    func resourceTitle(_ resource: ResourceMonitorKind) -> String {
        resourceTitles[resource] ?? resource.titleKey
    }

    func tabTitle(_ tab: NotchMetricsTab) -> String {
        tabTitles[tab] ?? tab.titleKey
    }

    func layoutTitle(_ style: MonitorLayoutStyle) -> String {
        layoutTitles[style] ?? style.localizedNameKey
    }

    func formatted(_ key: String, arguments: [CVarArg]) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    private static let keys = [
        "%@ free",
        "%d processes",
        "App",
        "App Usage",
        "App-level usage is not available for this resource.",
        "Apps",
        "Cached",
        "Cancel",
        "Charging",
        "Cycles",
        "Download",
        "Force Quit",
        "Force Quit App",
        "Force quitting %@ may lose unsaved work.",
        "Free",
        "Health",
        "Idle",
        "Model",
        "No app samples yet",
        "On Battery",
        "Plugged In",
        "Power",
        "Quit",
        "Received",
        "Render",
        "Sent",
        "Settings",
        "State",
        "System",
        "System-level data",
        "Temperature",
        "Tiler",
        "Total",
        "Upload",
        "Used",
        "User",
        "VRAM",
        "Waiting for next sample",
        "Wired"
    ]
}
