import AppKit
import CoreAudio
import Foundation

@MainActor
final class AudioControlStore: ObservableObject {
    static let shared = AudioControlStore()

    @Published private(set) var outputDevices: [AudioOutputDevice] = []
    @Published private(set) var appItems: [AudioAppVolumeItem] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var captureSupport: AudioCaptureSupportState = .available

    private let service = SystemAudioVolumeService()
    private let worker = AudioControlWorker()
    private let defaults: UserDefaults
    private var hasLoaded = false

    var defaultOutputDevice: AudioOutputDevice? {
        outputDevices.first { $0.isDefault }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        captureSupport = Self.currentCaptureSupport()
    }

    func refreshIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        worker.refresh(service: service) { [weak self] devices in
            Task { @MainActor in
                guard let self else { return }
                self.hasLoaded = true
                self.outputDevices = devices
                self.refreshAppItems()
                self.isRefreshing = false
                self.lastMessage = devices.isEmpty ? String(localized: "No output devices found.") : nil
            }
        }
    }

    func setDefaultOutputDevice(_ deviceID: AudioObjectID) {
        guard service.setDefaultOutputDevice(deviceID) else {
            lastMessage = String(localized: "Could not switch output device.")
            return
        }

        for index in outputDevices.indices {
            outputDevices[index].isDefault = outputDevices[index].id == deviceID
        }
        refresh()
    }

    func setDeviceVolume(_ value: Double, deviceID: AudioObjectID) {
        guard let index = outputDevices.firstIndex(where: { $0.id == deviceID }),
              outputDevices[index].supportsVolume else {
            return
        }

        let clamped = Self.clamp(value)
        outputDevices[index].volume = clamped
        let success = service.setDeviceVolume(clamped, deviceID: deviceID)
        if !success {
            outputDevices[index].volume = service.outputDevices().first { $0.id == deviceID }?.volume ?? outputDevices[index].volume
            lastMessage = String(localized: "Output device volume is unavailable.")
        } else {
            lastMessage = nil
        }
    }

    func setDeviceMuted(_ isMuted: Bool, deviceID: AudioObjectID) {
        guard let index = outputDevices.firstIndex(where: { $0.id == deviceID }),
              outputDevices[index].supportsMute else {
            return
        }

        outputDevices[index].isMuted = isMuted
        if !service.setDeviceMuted(isMuted, deviceID: deviceID) {
            outputDevices[index].isMuted.toggle()
            lastMessage = String(localized: "Output device mute is unavailable.")
        } else {
            lastMessage = nil
        }
    }

    func setAppVolume(_ value: Double, itemID: String) {
        updateAppItem(itemID) { item in
            item.volume = Self.clamp(value)
        }
    }

    func setAppMuted(_ isMuted: Bool, itemID: String) {
        updateAppItem(itemID) { item in
            item.isMuted = isMuted
        }
    }

    func setAppBoost(_ boost: AudioBoostLevel, itemID: String) {
        updateAppItem(itemID) { item in
            item.boost = boost
        }
    }

    func togglePinned(itemID: String) {
        updateAppItem(itemID) { item in
            item.isPinned.toggle()
        }
        refreshAppItems()
    }

    func toggleIgnored(itemID: String) {
        updateAppItem(itemID) { item in
            item.isIgnored.toggle()
        }
    }

    private func updateAppItem(
        _ itemID: String,
        update: (inout AudioAppVolumeItem) -> Void
    ) {
        guard let index = appItems.firstIndex(where: { $0.id == itemID }) else { return }

        update(&appItems[index])
        saveSettings(for: appItems[index])
        lastMessage = String(localized: "Per-app volume settings are saved locally until audio capture is enabled.")
    }

    private func refreshAppItems() {
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && app.bundleIdentifier != Bundle.main.bundleIdentifier
                    && !app.isTerminated
            }
            .sorted {
                ($0.localizedName ?? "") < ($1.localizedName ?? "")
            }

        var items = runningApps.map(audioItem(for:))

        let pinnedIDs = pinnedAppIDs()
        let existingIDs = Set(items.map(\.id))
        for pinnedID in pinnedIDs where !existingIDs.contains(pinnedID) {
            let settings = settings(for: pinnedID)
            items.append(AudioAppVolumeItem(
                id: pinnedID,
                name: pinnedDisplayName(for: pinnedID),
                bundleIdentifier: pinnedBundleIdentifier(for: pinnedID),
                processID: nil,
                icon: nil,
                isRunning: false,
                volume: settings.volume,
                isMuted: settings.isMuted,
                boost: boostLevel(for: settings.boost),
                isPinned: settings.isPinned,
                isIgnored: settings.isIgnored
            ))
        }

        appItems = items
    }

    private func audioItem(for app: NSRunningApplication) -> AudioAppVolumeItem {
        let id = storageID(for: app)
        let settings = settings(for: id)

        return AudioAppVolumeItem(
            id: id,
            name: app.localizedName ?? app.bundleIdentifier ?? String(localized: "Unknown App"),
            bundleIdentifier: app.bundleIdentifier,
            processID: app.processIdentifier,
            icon: app.icon,
            isRunning: true,
            volume: settings.volume,
            isMuted: settings.isMuted,
            boost: boostLevel(for: settings.boost),
            isPinned: settings.isPinned,
            isIgnored: settings.isIgnored
        )
    }

    private func storageID(for app: NSRunningApplication) -> String {
        if let bundleIdentifier = app.bundleIdentifier {
            return "bundle.\(bundleIdentifier)"
        }

        return "process.\(app.localizedName ?? "unknown").\(app.processIdentifier)"
    }

    private func settings(for id: String) -> AudioAppVolumeSettings {
        guard let data = defaults.data(forKey: settingsKey(for: id)),
              let settings = try? JSONDecoder().decode(AudioAppVolumeSettings.self, from: data) else {
            return .default
        }

        return settings
    }

    private func saveSettings(for item: AudioAppVolumeItem) {
        let settings = AudioAppVolumeSettings(
            volume: item.volume,
            isMuted: item.isMuted,
            boost: item.boost.rawValue,
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

    private func pinnedAppIDs() -> [String] {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("audio.app.settings.") }
            .compactMap { key -> String? in
                let id = String(key.dropFirst("audio.app.settings.".count))
                return settings(for: id).isPinned ? id : nil
            }
            .sorted()
    }

    private func pinnedDisplayName(for id: String) -> String {
        defaults.string(forKey: displayNameKey(for: id)) ?? String(localized: "Pinned App")
    }

    private func pinnedBundleIdentifier(for id: String) -> String? {
        defaults.string(forKey: bundleIdentifierKey(for: id))
    }

    private func boostLevel(for value: Double) -> AudioBoostLevel {
        AudioBoostLevel.allCases.first { $0.rawValue == value } ?? .x1
    }

    private func settingsKey(for id: String) -> String {
        "audio.app.settings.\(id)"
    }

    private func displayNameKey(for id: String) -> String {
        "audio.app.displayName.\(id)"
    }

    private func bundleIdentifierKey(for id: String) -> String {
        "audio.app.bundleIdentifier.\(id)"
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }

    private static func currentCaptureSupport() -> AudioCaptureSupportState {
        if #available(macOS 14.4, *) {
            return .available
        }

        return .unsupported(String(localized: "Per-app volume requires macOS 14.4 or later."))
    }
}

private final class AudioControlWorker {
    private let queue = DispatchQueue(label: "peakhalo.audio-control", qos: .userInitiated)

    func refresh(
        service: SystemAudioVolumeService,
        completion: @escaping ([AudioOutputDevice]) -> Void
    ) {
        queue.async {
            completion(service.outputDevices())
        }
    }
}
