import Foundation

struct StoredAudioAppMetadata: Equatable {
    let displayName: String?
    let bundleIdentifier: String?
}

final class AudioAppSettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func settings(for id: String) -> AudioAppVolumeSettings {
        guard let data = defaults.data(forKey: settingsKey(for: id)),
              let settings = try? JSONDecoder().decode(AudioAppVolumeSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    func saveSettings(for item: AudioAppVolumeItem) {
        let settings = AudioAppVolumeSettings(
            volume: item.volume,
            isMuted: item.isMuted,
            boost: item.boost.rawValue,
            outputDeviceUID: item.outputDeviceUID,
            outputRouteIntent: item.outputRouteIntent,
            equalizer: item.equalizer,
            isPinned: item.isPinned,
            isIgnored: item.isIgnored
        )

        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey(for: item.id))
        }

        defaults.set(item.name, forKey: displayNameKey(for: item.id))
        if let bundleIdentifier = item.bundleIdentifier {
            defaults.set(bundleIdentifier, forKey: bundleIdentifierKey(for: item.id))
        }
    }

    func pinnedAppIDs() -> [String] {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.settingsKeyPrefix) }
            .compactMap { key -> String? in
                let id = String(key.dropFirst(Self.settingsKeyPrefix.count))
                return settings(for: id).isPinned ? id : nil
            }
            .sorted()
    }

    func metadata(for id: String) -> StoredAudioAppMetadata {
        StoredAudioAppMetadata(
            displayName: defaults.string(forKey: displayNameKey(for: id)),
            bundleIdentifier: defaults.string(forKey: bundleIdentifierKey(for: id))
        )
    }

    private static let settingsKeyPrefix = "audio.app.settings."

    private func settingsKey(for id: String) -> String {
        "\(Self.settingsKeyPrefix)\(id)"
    }

    private func displayNameKey(for id: String) -> String {
        "audio.app.displayName.\(id)"
    }

    private func bundleIdentifierKey(for id: String) -> String {
        "audio.app.bundleIdentifier.\(id)"
    }
}
