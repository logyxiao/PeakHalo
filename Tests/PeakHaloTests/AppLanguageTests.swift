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
