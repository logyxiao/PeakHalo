import Foundation
import Testing
@testable import PeakHalo

@Suite("App language")
struct AppLanguageTests {
    @Test("Explicit languages resolve to bundled localizations")
    func explicitLanguagesResolveToBundledLocalizations() {
        #expect(
            AppLocalization.resolvedLocalizationIdentifier(
                for: .english,
                preferredLanguages: ["zh-Hans-CN"]
            ) == "en"
        )
        #expect(
            AppLocalization.resolvedLocalizationIdentifier(
                for: .simplifiedChinese,
                preferredLanguages: ["en-US"]
            ) == "zh-Hans"
        )
    }

    @Test("System language chooses supported localization")
    func systemLanguageChoosesSupportedLocalization() {
        let chinese = AppLocalization.resolvedLocalizationIdentifier(
            for: .system,
            preferredLanguages: ["zh-Hans-CN", "en-US"]
        )
        let english = AppLocalization.resolvedLocalizationIdentifier(
            for: .system,
            preferredLanguages: ["fr-FR", "en-US"]
        )

        #expect(chinese == "zh-Hans")
        #expect(english == "en")
    }

    @Test("Localized strings can be read from selected bundle")
    func localizedStringsCanBeReadFromSelectedBundle() {
        #expect(AppLocalization.localizedString("Language", language: .english) == "Language")
        #expect(AppLocalization.localizedString("Language", language: .simplifiedChinese) == "语言")
    }

    @Test("Runtime messages resolve through the selected language")
    func runtimeMessagesResolveThroughSelectedLanguage() {
        let message = LocalizedMessage("%d processes", arguments: [.int(3)])

        #expect(message.resolved(language: .english) == "3 processes")
        #expect(message.resolved(language: .simplifiedChinese) == "3 个进程")
    }

    @Test("Runtime messages support nested localized arguments")
    func runtimeMessagesSupportNestedLocalizedArguments() {
        let message = LocalizedMessage(
            "Sent %@ request to %@.",
            arguments: [.message(.string("force quit")), .string("Safari")]
        )

        #expect(message.resolved(language: .english) == "Sent force quit request to Safari.")
        #expect(message.resolved(language: .simplifiedChinese) == "已向 Safari 发送强制退出请求。")
    }

    @Test("Stored status messages are not fixed to one language")
    func storedStatusMessagesAreNotFixedToOneLanguage() {
        let captureSupport = AudioCaptureSupportState.permissionRequired(
            .string("Grant Screen & System Audio Recording permission to adjust per-app volume.")
        )
        let killResult = AppKillResult(
            success: false,
            message: LocalizedMessage(
                "%@ is protected and was not closed.",
                arguments: [.string("Finder")]
            )
        )

        #expect(captureSupport.message?.resolved(language: .english) == "Grant Screen & System Audio Recording permission to adjust per-app volume.")
        #expect(captureSupport.message?.resolved(language: .simplifiedChinese) == "授权“屏幕与系统音频录制”后才能调整应用单独音量。")
        #expect(killResult.message.resolved(language: .english) == "Finder is protected and was not closed.")
        #expect(killResult.message.resolved(language: .simplifiedChinese) == "Finder 受保护，未关闭。")
    }

    @MainActor
    @Test("Changing app language does not write AppleLanguages")
    func changingAppLanguageDoesNotWriteAppleLanguages() {
        let store = AppLanguageStore.shared
        let previousLanguage = store.language
        let defaults = UserDefaults.standard
        let domainName = Bundle.main.bundleIdentifier ?? "PeakHaloTests"
        let previousDomainAppleLanguages = defaults.persistentDomain(forName: domainName)?["AppleLanguages"]

        defaults.set(["en"], forKey: "AppleLanguages")
        store.setLanguage(.simplifiedChinese)

        #expect(defaults.string(forKey: "app.language") == AppLanguage.simplifiedChinese.rawValue)
        #expect(defaults.persistentDomain(forName: domainName)?["AppleLanguages"] == nil)
        #expect(store.localizedString("Language") == "语言")

        store.setLanguage(previousLanguage)
        if let previousDomainAppleLanguages {
            defaults.set(previousDomainAppleLanguages, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    @Test("Settings UI keys resolve through selected app language")
    func settingsUIKeysResolveThroughSelectedAppLanguage() {
        #expect(AppLocalization.localizedString("Search Settings", language: .simplifiedChinese) == "搜索设置")
        #expect(AppLocalization.localizedString("Display Placement", language: .simplifiedChinese) == "显示位置")
        #expect(AppLocalization.localizedString("Connected Displays", language: .simplifiedChinese) == "已连接显示器")
        #expect(AppLocalization.localizedString("Bluetooth Accessory Access", language: .simplifiedChinese) == "蓝牙配件访问")
        #expect(AppLocalization.localizedString("Open Source Credits", language: .simplifiedChinese) == "开源致谢")
        #expect(AppLocalization.localizedString(AppLanguage.simplifiedChinese.localizationKey, language: .simplifiedChinese) == "简体中文")
    }

    @Test("Language migration prefers an explicit stored language over stale system defaults")
    func languageMigrationPrefersExplicitStoredLanguage() {
        #expect(
            AppLanguageStore.resolvedStoredLanguage(
                primaryRaw: AppLanguage.system.rawValue,
                stableRaw: AppLanguage.system.rawValue,
                legacyRaw: AppLanguage.simplifiedChinese.rawValue
            ) == .simplifiedChinese
        )
        #expect(
            AppLanguageStore.resolvedStoredLanguage(
                primaryRaw: AppLanguage.english.rawValue,
                stableRaw: AppLanguage.simplifiedChinese.rawValue,
                legacyRaw: nil
            ) == .english
        )
        #expect(
            AppLanguageStore.resolvedStoredLanguage(
                primaryRaw: nil,
                stableRaw: nil,
                legacyRaw: nil
            ) == .system
        )
    }

    @Test("Repeated settings localization lookups stay responsive")
    func repeatedSettingsLocalizationLookupsStayResponsive() {
        let keys = [
            "Search Settings",
            "Display Placement",
            "Connected Displays",
            "Bluetooth Accessory Access",
            "Open Source Credits",
            "Choose the language used by PeakHalo.",
            "Click the menu bar icon to expand or collapse the controls."
        ]

        let start = Date()
        for _ in 0..<500 {
            for key in keys {
                _ = AppLocalization.localizedString(key, language: .simplifiedChinese)
            }
        }

        #expect(Date().timeIntervalSince(start) < 1.0)
    }

    @Test("Repeated metrics localization snapshots stay responsive")
    func repeatedMetricsLocalizationSnapshotsStayResponsive() {
        _ = LocalizedMetricsStrings.cached(for: .simplifiedChinese)

        let start = Date()
        for _ in 0..<5_000 {
            let strings = LocalizedMetricsStrings.cached(for: .simplifiedChinese)
            _ = strings.resourceTitle(.cpu)
            _ = strings.text("App Usage")
            _ = strings.formatted("%d processes", arguments: [3])
        }

        #expect(Date().timeIntervalSince(start) < 0.25)
    }

    @Test("Packaged app resource directories are resolved without Bundle.module")
    func packagedAppResourceDirectoriesAreResolvedWithoutBundleModule() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resourcesDirectory = temporaryDirectory
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let englishDirectory = resourcesDirectory.appendingPathComponent("en.lproj", isDirectory: true)
        let chineseDirectory = resourcesDirectory.appendingPathComponent("zh-hans.lproj", isDirectory: true)

        try FileManager.default.createDirectory(
            at: englishDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: chineseDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try #""Language" = "Language";"#.write(
            to: englishDirectory.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )
        try #""Language" = "语言";"#.write(
            to: chineseDirectory.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )

        #expect(
            AppLocalization.localizedString(
                "Language",
                language: .simplifiedChinese,
                searchDirectories: [resourcesDirectory]
            ) == "语言"
        )
    }
}
