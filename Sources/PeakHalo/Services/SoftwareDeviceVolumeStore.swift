import Foundation

final class SoftwareDeviceVolumeStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func volume(uid: String) -> Double {
        if let value = defaults.object(forKey: volumeKey(uid)) as? Double {
            return DeviceMutePolicy.clamp(value)
        }

        if let value = defaults.object(forKey: volumeKey(uid)) as? NSNumber {
            return DeviceMutePolicy.clamp(value.doubleValue)
        }

        return mutedFlag(uid: uid) ? 0 : 100
    }

    func isMuted(uid: String) -> Bool {
        mutedFlag(uid: uid) || volume(uid: uid) <= 0
    }

    func processingGain(uid: String) -> Double {
        guard !isMuted(uid: uid) else { return 0 }
        return min(1, max(0, volume(uid: uid) / 100))
    }

    func setVolume(_ value: Double, uid: String) {
        let policy = DeviceMutePolicy.volumeWrite(value)
        defaults.set(policy.visibleVolume, forKey: volumeKey(uid))
        if let restoreVolume = policy.restoreVolumeToSave {
            defaults.set(restoreVolume, forKey: restoreVolumeKey(uid))
        }
        defaults.set(policy.isMuted, forKey: mutedKey(uid))
    }

    @discardableResult
    func setMuted(_ isMuted: Bool, uid: String) -> Double {
        let policy = isMuted
            ? DeviceMutePolicy.mute(currentVolume: volume(uid: uid))
            : DeviceMutePolicy.unmute(
                currentVolume: volume(uid: uid),
                savedRestoreVolume: restoreVolume(uid: uid),
                storedVolume: nil,
                defaultVolume: 50
            )

        if let restoreVolume = policy.restoreVolumeToSave {
            defaults.set(restoreVolume, forKey: restoreVolumeKey(uid))
        }
        defaults.set(policy.visibleVolume, forKey: volumeKey(uid))
        defaults.set(policy.isMuted, forKey: mutedKey(uid))
        return policy.visibleVolume
    }

    private func mutedFlag(uid: String) -> Bool {
        defaults.bool(forKey: mutedKey(uid))
    }

    private func restoreVolume(uid: String) -> Double? {
        if let value = defaults.object(forKey: restoreVolumeKey(uid)) as? Double {
            let clamped = DeviceMutePolicy.clamp(value)
            return clamped > 0 ? clamped : nil
        }

        if let value = defaults.object(forKey: restoreVolumeKey(uid)) as? NSNumber {
            let clamped = DeviceMutePolicy.clamp(value.doubleValue)
            return clamped > 0 ? clamped : nil
        }

        return nil
    }

    private func volumeKey(_ uid: String) -> String {
        "audio.softwareDevice.volume.\(uid)"
    }

    private func mutedKey(_ uid: String) -> String {
        "audio.softwareDevice.muted.\(uid)"
    }

    private func restoreVolumeKey(_ uid: String) -> String {
        "audio.softwareDevice.restoreVolume.\(uid)"
    }
}
