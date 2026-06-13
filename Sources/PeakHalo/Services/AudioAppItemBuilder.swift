import AppKit
import Foundation

struct RunningAudioAppDescriptor {
    let processID: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let icon: NSImage?
}

struct AudioAppItemBuildResult {
    let items: [AudioAppVolumeItem]
    let existingIDs: Set<String>
}

enum AudioAppItemBuilder {
    static func buildItems(
        audioProcesses: [AudioProcessInfo],
        runningApps: [RunningAudioAppDescriptor],
        settingsStore: AudioAppSettingsStore,
        audioProcessFallbackName: String,
        pinnedFallbackName: String
    ) -> AudioAppItemBuildResult {
        let appsByPID = Dictionary(
            runningApps.map { ($0.processID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let appsByBundleID = Dictionary(
            runningApps.compactMap { app -> (String, RunningAudioAppDescriptor)? in
                guard let bundleIdentifier = app.bundleIdentifier else { return nil }
                return (bundleIdentifier, app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var groupedAudioProcesses: [String: [AudioProcessInfo]] = [:]
        var representativeApps: [String: RunningAudioAppDescriptor] = [:]

        for process in audioProcesses {
            let app = appsByPID[process.processID]
                ?? process.bundleIdentifier.flatMap { appsByBundleID[$0] }
            let id = app.map(storageID(for:))
                ?? process.bundleIdentifier.map { "bundle.\($0)" }
                ?? "process.\(process.processID)"

            groupedAudioProcesses[id, default: []].append(process)
            if let app {
                representativeApps[id] = app
            }
        }

        var items = groupedAudioProcesses.keys.sorted().map { id in
            audioItem(
                id: id,
                app: representativeApps[id],
                processes: groupedAudioProcesses[id] ?? [],
                settingsStore: settingsStore,
                fallbackName: audioProcessFallbackName
            )
        }

        var existingIDs = Set(items.map(\.id))
        for app in runningApps.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
            let id = storageID(for: app)
            guard !existingIDs.contains(id) else { continue }
            items.append(audioItem(
                id: id,
                app: app,
                processes: [],
                settingsStore: settingsStore,
                fallbackName: audioProcessFallbackName
            ))
            existingIDs.insert(id)
        }

        for pinnedID in settingsStore.pinnedAppIDs() where !existingIDs.contains(pinnedID) {
            let settings = settingsStore.settings(for: pinnedID)
            let metadata = settingsStore.metadata(for: pinnedID)
            items.append(AudioAppVolumeItem(
                id: pinnedID,
                name: metadata.displayName ?? pinnedFallbackName,
                bundleIdentifier: metadata.bundleIdentifier,
                processID: nil,
                audioProcessObjectIDs: [],
                icon: nil,
                isRunning: false,
                isAudible: false,
                volume: settings.volume,
                isMuted: settings.isMuted,
                boost: boostLevel(for: settings.boost),
                outputDeviceUID: settings.outputDeviceUID,
                outputRouteIntent: settings.outputRouteIntent,
                equalizer: settings.equalizer,
                isPinned: settings.isPinned,
                isIgnored: settings.isIgnored
            ))
            existingIDs.insert(pinnedID)
        }

        return AudioAppItemBuildResult(items: items, existingIDs: existingIDs)
    }

    static func storageID(for app: RunningAudioAppDescriptor) -> String {
        if let bundleIdentifier = app.bundleIdentifier {
            return "bundle.\(bundleIdentifier)"
        }

        return "process.\(app.localizedName ?? "unknown").\(app.processID)"
    }

    private static func audioItem(
        id: String,
        app: RunningAudioAppDescriptor?,
        processes: [AudioProcessInfo],
        settingsStore: AudioAppSettingsStore,
        fallbackName: String
    ) -> AudioAppVolumeItem {
        let settings = settingsStore.settings(for: id)
        let representativeProcess = processes.first

        return AudioAppVolumeItem(
            id: id,
            name: app?.localizedName
                ?? app?.bundleIdentifier
                ?? representativeProcess?.displayName
                ?? representativeProcess?.bundleIdentifier
                ?? fallbackName,
            bundleIdentifier: app?.bundleIdentifier ?? representativeProcess?.bundleIdentifier,
            processID: app?.processID ?? representativeProcess?.processID,
            audioProcessObjectIDs: processes.map(\.objectID),
            icon: app?.icon ?? representativeProcess?.icon,
            isRunning: app != nil || !processes.isEmpty,
            isAudible: processes.contains { $0.isRunningOutput },
            volume: settings.volume,
            isMuted: settings.isMuted,
            boost: boostLevel(for: settings.boost),
            outputDeviceUID: settings.outputDeviceUID,
            outputRouteIntent: settings.outputRouteIntent,
            equalizer: settings.equalizer,
            isPinned: settings.isPinned,
            isIgnored: settings.isIgnored
        )
    }

    private static func boostLevel(for value: Double) -> AudioBoostLevel {
        AudioBoostLevel.allCases.first { $0.rawValue == value } ?? .x1
    }
}
