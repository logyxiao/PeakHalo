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

    @Test("Route resolver keeps system default route stream-specific")
    func routeResolverKeepsSystemDefaultRouteStreamSpecific() throws {
        let defaultDevice = outputDevice(id: 10, uid: "device-a", volume: 50, muted: false)
        let item = appItem(routeIntent: .systemDefault)

        let resolution = try #require(AudioRouteResolver.resolve(
            for: item,
            outputDevices: [defaultDevice],
            defaultOutputDevice: defaultDevice
        ))

        #expect(resolution.usedFallback == false)
        #expect(resolution.route.followsSystemDefault)
        #expect(resolution.route.preferredTapSourceDeviceUID == "device-a")
    }

    @Test("Route resolver falls back when explicit device is unavailable")
    func routeResolverFallsBackWhenExplicitDeviceIsUnavailable() throws {
        let defaultDevice = outputDevice(id: 10, uid: "device-a", volume: 50, muted: false)
        let item = appItem(routeIntent: .single("missing-device"))

        let resolution = try #require(AudioRouteResolver.resolve(
            for: item,
            outputDevices: [defaultDevice],
            defaultOutputDevice: defaultDevice
        ))

        #expect(resolution.usedFallback)
        #expect(resolution.route.outputDeviceUID == "device-a")
        #expect(resolution.route.followsSystemDefault == false)
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

    private func appItem(routeIntent: AudioAppOutputRouteIntent) -> AudioAppVolumeItem {
        AudioAppVolumeItem(
            id: "bundle.test",
            name: "Test",
            bundleIdentifier: "com.example.test",
            processID: 123,
            audioProcessObjectIDs: [1],
            icon: nil,
            isRunning: true,
            isAudible: true,
            volume: 100,
            isMuted: false,
            boost: .x1,
            outputDeviceUID: routeIntent.primaryOutputDeviceUID,
            outputRouteIntent: routeIntent,
            equalizer: .flat,
            isPinned: false,
            isIgnored: false
        )
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
