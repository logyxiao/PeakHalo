import Foundation

struct DeviceMutePolicy {
    let visibleVolume: Double
    let isMuted: Bool
    let restoreVolumeToSave: Double?

    static func volumeWrite(_ value: Double) -> DeviceMutePolicy {
        let clamped = clamp(value)
        return DeviceMutePolicy(
            visibleVolume: clamped,
            isMuted: clamped <= 0,
            restoreVolumeToSave: clamped > 0 ? clamped : nil
        )
    }

    static func mute(currentVolume: Double) -> DeviceMutePolicy {
        let current = clamp(currentVolume)
        return DeviceMutePolicy(
            visibleVolume: 0,
            isMuted: true,
            restoreVolumeToSave: current > 0 ? current : nil
        )
    }

    static func unmute(
        currentVolume: Double,
        savedRestoreVolume: Double?,
        storedVolume: Double?,
        defaultVolume: Double
    ) -> DeviceMutePolicy {
        let current = clamp(currentVolume)
        guard current <= 0 else {
            return DeviceMutePolicy(
                visibleVolume: current,
                isMuted: false,
                restoreVolumeToSave: nil
            )
        }

        let restored = positiveClamped(savedRestoreVolume)
            ?? positiveClamped(storedVolume)
            ?? positiveClamped(defaultVolume)
            ?? 1
        let visibleVolume = max(1, restored)
        return DeviceMutePolicy(
            visibleVolume: visibleVolume,
            isMuted: false,
            restoreVolumeToSave: nil
        )
    }

    static func volumeAfterSettingMuted(
        _ isMuted: Bool,
        currentVolume: Double,
        savedRestoreVolume: Double?,
        storedVolume: Double?,
        defaultVolume: Double
    ) -> Double {
        if isMuted { return 0 }
        return unmute(
            currentVolume: currentVolume,
            savedRestoreVolume: savedRestoreVolume,
            storedVolume: storedVolume,
            defaultVolume: defaultVolume
        ).visibleVolume
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }

    private static func positiveClamped(_ value: Double?) -> Double? {
        guard let value else { return nil }
        let clamped = clamp(value)
        return clamped > 0 ? clamped : nil
    }
}
