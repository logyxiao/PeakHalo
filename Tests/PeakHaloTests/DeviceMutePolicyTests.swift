import Testing
@testable import PeakHalo

@Suite("Device mute policy")
struct DeviceMutePolicyTests {
    @Test("Volume write to zero marks muted without restore volume")
    func volumeWriteToZeroMarksMuted() {
        let policy = DeviceMutePolicy.volumeWrite(0)

        #expect(policy.visibleVolume == 0)
        #expect(policy.isMuted)
        #expect(policy.restoreVolumeToSave == nil)
    }

    @Test("Positive volume write clears mute and saves restore volume")
    func positiveVolumeWriteClearsMute() {
        let policy = DeviceMutePolicy.volumeWrite(72)

        #expect(policy.visibleVolume == 72)
        #expect(policy.isMuted == false)
        #expect(policy.restoreVolumeToSave == 72)
    }

    @Test("Mute saves current positive volume and writes zero")
    func muteSavesCurrentPositiveVolume() {
        let policy = DeviceMutePolicy.mute(currentVolume: 35)

        #expect(policy.visibleVolume == 0)
        #expect(policy.isMuted)
        #expect(policy.restoreVolumeToSave == 35)
    }

    @Test("Unmute prefers saved restore volume")
    func unmutePrefersSavedRestoreVolume() {
        let policy = DeviceMutePolicy.unmute(
            currentVolume: 0,
            savedRestoreVolume: 64,
            storedVolume: 20,
            defaultVolume: 50
        )

        #expect(policy.visibleVolume == 64)
        #expect(policy.isMuted == false)
    }

    @Test("Unmute falls back to stored then default with minimum audible volume")
    func unmuteFallsBackToStoredThenDefault() {
        let stored = DeviceMutePolicy.unmute(
            currentVolume: 0,
            savedRestoreVolume: nil,
            storedVolume: 20,
            defaultVolume: 50
        )
        let defaulted = DeviceMutePolicy.unmute(
            currentVolume: 0,
            savedRestoreVolume: nil,
            storedVolume: nil,
            defaultVolume: 0
        )

        #expect(stored.visibleVolume == 20)
        #expect(defaulted.visibleVolume == 1)
    }

    @Test("Unmute keeps current positive volume")
    func unmuteKeepsCurrentPositiveVolume() {
        let policy = DeviceMutePolicy.unmute(
            currentVolume: 33,
            savedRestoreVolume: 64,
            storedVolume: 20,
            defaultVolume: 50
        )

        #expect(policy.visibleVolume == 33)
    }
}
