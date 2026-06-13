import Foundation
import Testing
@testable import PeakHalo

@Suite("Audio app settings store")
struct AudioAppSettingsStoreTests {
    @Test("Saved app settings round-trip with metadata")
    func savedSettingsRoundTripWithMetadata() {
        let suiteName = "PeakHaloTests.AudioAppSettingsStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AudioAppSettingsStore(defaults: defaults)
        let item = appItem(
            id: "bundle.com.example.music",
            name: "Music App",
            bundleIdentifier: "com.example.music",
            isPinned: true
        )

        store.saveSettings(for: item)

        let settings = store.settings(for: item.id)
        let metadata = store.metadata(for: item.id)
        #expect(settings.volume == 55)
        #expect(settings.isMuted)
        #expect(settings.boost == AudioBoostLevel.x2.rawValue)
        #expect(settings.outputRouteIntent == .single("device-a"))
        #expect(settings.isPinned)
        #expect(metadata.displayName == "Music App")
        #expect(metadata.bundleIdentifier == "com.example.music")
        #expect(store.pinnedAppIDs() == [item.id])
    }

    @Test("Missing app settings use defaults")
    func missingSettingsUseDefaults() {
        let suiteName = "PeakHaloTests.AudioAppSettingsStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AudioAppSettingsStore(defaults: defaults)

        #expect(store.settings(for: "missing") == .default)
        #expect(store.pinnedAppIDs().isEmpty)
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
            isMuted: true,
            boost: .x2,
            outputDeviceUID: "device-a",
            outputRouteIntent: .single("device-a"),
            equalizer: .flat,
            isPinned: isPinned,
            isIgnored: false
        )
    }
}
