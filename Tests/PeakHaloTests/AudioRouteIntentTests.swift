import CoreAudio
import Foundation
import Testing
@testable import PeakHalo

@Suite("Audio route intent")
struct AudioRouteIntentTests {
    @Test("Old single-device settings migrate to single route intent")
    func oldSingleDeviceSettingsMigration() throws {
        let json = """
        {
          "volume": 72,
          "isMuted": false,
          "boost": 2,
          "outputDeviceUID": "device-a",
          "isPinned": true,
          "isIgnored": false
        }
        """
        let data = try #require(json.data(using: .utf8))

        let settings = try JSONDecoder().decode(AudioAppVolumeSettings.self, from: data)

        #expect(settings.outputDeviceUID == "device-a")
        #expect(settings.outputRouteIntent == .single("device-a"))
        #expect(settings.isPinned)
    }

    @Test("Multi route toggles devices without duplicates")
    func multiRouteToggle() {
        var route = AudioAppOutputRouteIntent.multi(["device-a"])

        route = route.togglingMultiDevice("device-b")
        #expect(route == .multi(["device-a", "device-b"]))

        route = route.togglingMultiDevice("device-a")
        #expect(route == .multi(["device-b"]))

        route = route.togglingMultiDevice("device-b")
        #expect(route == .systemDefault)
    }

    @Test("Tap routes compare by output identity, not volatile volume state")
    func routeEqualityIgnoresDeviceVolumeState() {
        let first = AudioProcessTapRoute(
            outputDeviceID: AudioObjectID(10),
            outputDeviceUID: "device-a",
            outputDevices: [
                outputDevice(id: 10, uid: "device-a", volume: 20, muted: false)
            ],
            followsSystemDefault: false,
            preferredTapSourceDeviceUID: nil
        )
        let second = AudioProcessTapRoute(
            outputDeviceID: AudioObjectID(10),
            outputDeviceUID: "device-a",
            outputDevices: [
                outputDevice(id: 10, uid: "device-a", volume: 90, muted: true)
            ],
            followsSystemDefault: false,
            preferredTapSourceDeviceUID: nil
        )

        #expect(first == second)
    }

    @Test("Software-backed devices expose processing gain")
    func softwareBackedDeviceProcessingGain() {
        let active = outputDevice(
            id: 10,
            uid: "device-a",
            volume: 40,
            muted: false,
            volumeBackend: .software
        )
        let muted = outputDevice(
            id: 11,
            uid: "device-b",
            volume: 80,
            muted: true,
            volumeBackend: .software
        )
        let hardware = outputDevice(
            id: 12,
            uid: "device-c",
            volume: 25,
            muted: false,
            volumeBackend: .hardware
        )

        #expect(active.softwareProcessingGain == 0.4)
        #expect(muted.softwareProcessingGain == 0)
        #expect(hardware.softwareProcessingGain == 1)
    }

    private func outputDevice(
        id: AudioObjectID,
        uid: String,
        volume: Double,
        muted: Bool,
        volumeBackend: AudioOutputVolumeBackend = .hardware
    ) -> AudioOutputDevice {
        AudioOutputDevice(
            id: id,
            uid: uid,
            name: uid,
            transportName: "Test",
            isDefault: false,
            volume: volume,
            isMuted: muted,
            volumeBackend: volumeBackend,
            supportsVolume: true,
            supportsMute: true,
            unavailableReason: nil
        )
    }
}
