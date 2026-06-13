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
}
