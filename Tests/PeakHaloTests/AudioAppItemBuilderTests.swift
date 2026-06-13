import CoreAudio
import Foundation
import Testing
@testable import PeakHalo

@Suite("Audio app item builder")
struct AudioAppItemBuilderTests {
    @Test("Audio processes merge into responsible running apps")
    func audioProcessesMergeIntoResponsibleRunningApps() {
        let suiteName = "PeakHaloTests.AudioAppItemBuilder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AudioAppSettingsStore(defaults: defaults)
        let app = RunningAudioAppDescriptor(
            processID: 100,
            bundleIdentifier: "com.example.music",
            localizedName: "Music",
            icon: nil
        )
        let process = AudioProcessInfo(
            objectID: AudioObjectID(10),
            processID: 100,
            bundleIdentifier: "com.example.music.helper",
            displayName: "Helper",
            isRunningOutput: true,
            isHelperBacked: true
        )

        let result = AudioAppItemBuilder.buildItems(
            audioProcesses: [process],
            runningApps: [app],
            settingsStore: store,
            audioProcessFallbackName: "Audio Process",
            pinnedFallbackName: "Pinned App"
        )

        #expect(result.items.count == 1)
        #expect(result.items[0].id == "bundle.com.example.music")
        #expect(result.items[0].name == "Music")
        #expect(result.items[0].audioProcessObjectIDs == [10])
        #expect(result.items[0].isAudible)
    }

    @Test("Pinned apps are restored when not running")
    func pinnedAppsAreRestoredWhenNotRunning() {
        let suiteName = "PeakHaloTests.AudioAppItemBuilder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AudioAppSettingsStore(defaults: defaults)
        store.saveSettings(for: appItem(
            id: "bundle.com.example.pinned",
            name: "Pinned Music",
            bundleIdentifier: "com.example.pinned",
            isPinned: true
        ))

        let result = AudioAppItemBuilder.buildItems(
            audioProcesses: [],
            runningApps: [],
            settingsStore: store,
            audioProcessFallbackName: "Audio Process",
            pinnedFallbackName: "Pinned App"
        )

        #expect(result.items.count == 1)
        #expect(result.items[0].id == "bundle.com.example.pinned")
        #expect(result.items[0].name == "Pinned Music")
        #expect(result.items[0].isRunning == false)
        #expect(result.items[0].isPinned)
    }

    private func appItem(
        id: String,
        name: String,
        bundleIdentifier: String?,
        isPinned: Bool
    ) -> AudioAppVolumeItem {
        AudioAppVolumeItem(
            id: id,
            name: name,
            bundleIdentifier: bundleIdentifier,
            processID: 123,
            audioProcessObjectIDs: [1],
            icon: nil,
            isRunning: true,
            isAudible: true,
            volume: 55,
            isMuted: false,
            boost: .x1,
            outputDeviceUID: nil,
            outputRouteIntent: .systemDefault,
            equalizer: .flat,
            isPinned: isPinned,
            isIgnored: false
        )
    }
}
