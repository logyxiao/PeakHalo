import Foundation
import Testing
@testable import PeakHalo

@Suite("Software device volume store")
struct SoftwareDeviceVolumeStoreTests {
    @Test("Missing software volume defaults to audible")
    func missingVolumeDefaultsToAudible() {
        let (store, suiteName, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(store.volume(uid: "device") == 100)
        #expect(store.isMuted(uid: "device") == false)
        #expect(store.processingGain(uid: "device") == 1)
    }

    @Test("Setting volume to zero mutes and clears gain")
    func settingVolumeToZeroMutes() {
        let (store, suiteName, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.setVolume(0, uid: "device")

        #expect(store.volume(uid: "device") == 0)
        #expect(store.isMuted(uid: "device"))
        #expect(store.processingGain(uid: "device") == 0)
    }

    @Test("Mute saves restore volume and unmute restores it")
    func muteSavesRestoreVolumeAndUnmuteRestoresIt() {
        let (store, suiteName, defaults) = makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.setVolume(42, uid: "device")
        #expect(store.setMuted(true, uid: "device") == 0)
        #expect(store.volume(uid: "device") == 0)
        #expect(store.isMuted(uid: "device"))

        #expect(store.setMuted(false, uid: "device") == 42)
        #expect(store.volume(uid: "device") == 42)
        #expect(store.isMuted(uid: "device") == false)
    }

    private func makeStore() -> (SoftwareDeviceVolumeStore, String, UserDefaults) {
        let suiteName = "PeakHaloTests.SoftwareDeviceVolumeStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (SoftwareDeviceVolumeStore(defaults: defaults), suiteName, defaults)
    }
}
