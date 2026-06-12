import AppKit
import CoreAudio
import Darwin
import Foundation

@MainActor
final class AudioControlStore: ObservableObject {
    static let shared = AudioControlStore()

    @Published private(set) var outputDevices: [AudioOutputDevice] = []
    @Published private(set) var appItems: [AudioAppVolumeItem] = []
    @Published private(set) var processingAppIDs: Set<String> = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastMessage: String?
    @Published private(set) var captureSupport: AudioCaptureSupportState = .available

    private let service = SystemAudioVolumeService()
    private let processService = AudioProcessService()
    private let processTapService = AudioProcessTapService()
    private let worker = AudioControlWorker()
    private let defaults: UserDefaults
    private var hasLoaded = false
    private var monitorTask: Task<Void, Never>?

    var defaultOutputDevice: AudioOutputDevice? {
        outputDevices.first { $0.isDefault }
    }

    var canControlAppAudio: Bool {
        captureSupport.allowsAppAudioControl
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        captureSupport = Self.currentCaptureSupport()
    }

    func refreshIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func startMonitoring() {
        refreshCaptureSupport()
        refreshIfNeeded()
        processService.startMonitoring { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }

        guard monitorTask == nil else { return }

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await MainActor.run {
                    self?.refresh()
                }
            }
        }
    }

    func stopMonitoring() {
        processService.stopMonitoring()
        monitorTask?.cancel()
        monitorTask = nil
    }

    func shutdown() {
        stopMonitoring()
        processTapService.deactivateAll()
        processingAppIDs.removeAll()
    }

    func refresh() {
        guard !isRefreshing else { return }

        refreshCaptureSupport()
        isRefreshing = true
        worker.refresh(service: service, processService: processService) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.hasLoaded = true
                self.outputDevices = result.devices
                self.refreshAppItems(audioProcesses: result.audioProcesses)
                self.isRefreshing = false
                self.lastMessage = result.devices.isEmpty ? String(localized: "No output devices found.") : nil
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

        worker.setDeviceVolume(
            clamped,
            deviceID: deviceID,
            service: service
        ) { [weak self] result in
            Task { @MainActor in
                self?.applyDeviceVolumeWrite(result)
            }
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
        guard canControlAppAudio else {
            showAppAudioPermissionMessage()
            return
        }

        updateAppItem(itemID) { item in
            item.volume = Self.clamp(value)
        }
        updateProcessingState(itemID: itemID)
    }

    func setAppMuted(_ isMuted: Bool, itemID: String) {
        guard canControlAppAudio else {
            showAppAudioPermissionMessage()
            return
        }

        updateAppItem(itemID) { item in
            item.isMuted = isMuted
        }
        updateProcessingState(itemID: itemID)
    }

    func setAppBoost(_ boost: AudioBoostLevel, itemID: String) {
        guard canControlAppAudio else {
            showAppAudioPermissionMessage()
            return
        }

        updateAppItem(itemID) { item in
            item.boost = boost
        }
        updateProcessingState(itemID: itemID)
    }

    func setAppOutputDevice(_ outputDeviceUID: String?, itemID: String) {
        guard canControlAppAudio else {
            showAppAudioPermissionMessage()
            return
        }

        updateAppItem(itemID) { item in
            item.outputDeviceUID = outputDeviceUID
        }

        guard processingAppIDs.contains(itemID) else { return }
        restartProcessing(itemID: itemID)
    }

    func playbackDeviceTitle(for item: AudioAppVolumeItem) -> String {
        guard let uid = item.outputDeviceUID else {
            return String(localized: "System Default")
        }

        return outputDevices.first { $0.uid == uid }?.name ?? String(localized: "Unknown Output")
    }

    func isProcessingEnabled(itemID: String) -> Bool {
        processingAppIDs.contains(itemID)
    }

    func toggleProcessing(itemID: String) {
        guard canControlAppAudio else {
            showAppAudioPermissionMessage()
            return
        }

        if processingAppIDs.contains(itemID) {
            deactivateProcessing(itemID: itemID)
            return
        }

        guard let item = appItems.first(where: { $0.id == itemID }) else { return }
        processTapService.activate(
            itemID: itemID,
            processObjectIDs: item.audioProcessObjectIDs,
            outputDeviceUID: resolvedOutputDeviceUID(for: item),
            volume: item.volume,
            isMuted: item.isMuted,
            boost: item.boost
        ) { [weak self] result in
            Task { @MainActor in
                self?.applyTapResult(result, enabling: true)
            }
        }
    }

    func togglePinned(itemID: String) {
        updateAppItem(itemID, showSavedMessage: false) { item in
            item.isPinned.toggle()
        }
        refresh()
    }

    func toggleIgnored(itemID: String) {
        updateAppItem(itemID, showSavedMessage: false) { item in
            item.isIgnored.toggle()
        }
        appItems = sortedAppItems(appItems)
    }

    func refreshCaptureSupport() {
        let nextState = Self.currentCaptureSupport()
        captureSupport = nextState

        if !nextState.allowsAppAudioControl, !processingAppIDs.isEmpty {
            processTapService.deactivateAll()
            processingAppIDs.removeAll()
            appItems = sortedAppItems(appItems)
        }
    }

    private func updateAppItem(
        _ itemID: String,
        showSavedMessage: Bool = true,
        update: (inout AudioAppVolumeItem) -> Void
    ) {
        guard let index = appItems.firstIndex(where: { $0.id == itemID }) else { return }

        update(&appItems[index])
        saveSettings(for: appItems[index])
        if showSavedMessage {
            lastMessage = nil
        }
    }

    private func refreshAppItems(audioProcesses: [AudioProcessInfo]) {
        let previousItems = Dictionary(
            appItems.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && app.bundleIdentifier != Bundle.main.bundleIdentifier
                    && !app.isTerminated
            }
            .sorted {
                ($0.localizedName ?? "") < ($1.localizedName ?? "")
            }

        let appsByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })
        let appsByBundleID = Dictionary(
            runningApps.compactMap { app -> (String, NSRunningApplication)? in
                guard let bundleIdentifier = app.bundleIdentifier else { return nil }
                return (bundleIdentifier, app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var groupedAudioProcesses: [String: [AudioProcessInfo]] = [:]
        var representativeApps: [String: NSRunningApplication] = [:]

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
                processes: groupedAudioProcesses[id] ?? []
            )
        }

        let pinnedIDs = pinnedAppIDs()
        let existingIDs = Set(items.map(\.id))
        for pinnedID in pinnedIDs where !existingIDs.contains(pinnedID) {
            let settings = settings(for: pinnedID)
            items.append(AudioAppVolumeItem(
                id: pinnedID,
                name: pinnedDisplayName(for: pinnedID),
                bundleIdentifier: pinnedBundleIdentifier(for: pinnedID),
                processID: nil,
                audioProcessObjectIDs: [],
                icon: nil,
                isRunning: false,
                isAudible: false,
                volume: settings.volume,
                isMuted: settings.isMuted,
                boost: boostLevel(for: settings.boost),
                outputDeviceUID: settings.outputDeviceUID,
                isPinned: settings.isPinned,
                isIgnored: settings.isIgnored
            ))
        }

        if items.isEmpty {
            items = runningApps.prefix(5).map(audioItem(for:))
        }

        appItems = sortedAppItems(items)
        synchronizeProcessing(previousItems: previousItems, currentItems: items)
    }

    private func audioItem(for app: NSRunningApplication) -> AudioAppVolumeItem {
        audioItem(id: storageID(for: app), app: app, processes: [])
    }

    private func audioItem(
        id: String,
        app: NSRunningApplication?,
        processes: [AudioProcessInfo]
    ) -> AudioAppVolumeItem {
        let settings = settings(for: id)

        return AudioAppVolumeItem(
            id: id,
            name: app?.localizedName
                ?? app?.bundleIdentifier
                ?? processes.first?.bundleIdentifier
                ?? String(localized: "Audio Process"),
            bundleIdentifier: app?.bundleIdentifier ?? processes.first?.bundleIdentifier,
            processID: app?.processIdentifier ?? processes.first?.processID,
            audioProcessObjectIDs: processes.map(\.objectID),
            icon: app?.icon,
            isRunning: app != nil,
            isAudible: processes.contains { $0.isRunningOutput },
            volume: settings.volume,
            isMuted: settings.isMuted,
            boost: boostLevel(for: settings.boost),
            outputDeviceUID: settings.outputDeviceUID,
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
            outputDeviceUID: item.outputDeviceUID,
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

    private func sortedAppItems(_ items: [AudioAppVolumeItem]) -> [AudioAppVolumeItem] {
        items.sorted { lhs, rhs in
            if lhs.isIgnored != rhs.isIgnored {
                return !lhs.isIgnored
            }

            if lhs.isAudible != rhs.isAudible {
                return lhs.isAudible
            }

            let lhsIsProcessing = processingAppIDs.contains(lhs.id)
            let rhsIsProcessing = processingAppIDs.contains(rhs.id)
            if lhsIsProcessing != rhsIsProcessing {
                return lhsIsProcessing
            }

            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }

            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning
            }

            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }

            return lhs.id < rhs.id
        }
    }

    private func settingsKey(for id: String) -> String {
        "audio.app.settings.\(id)"
    }

    private func updateProcessingState(itemID: String) {
        guard canControlAppAudio else { return }
        guard processingAppIDs.contains(itemID),
              let item = appItems.first(where: { $0.id == itemID }) else {
            return
        }

        processTapService.update(
            itemID: itemID,
            volume: item.volume,
            isMuted: item.isMuted,
            boost: item.boost
        )
    }

    private func restartProcessing(itemID: String) {
        guard canControlAppAudio else { return }
        guard let item = appItems.first(where: { $0.id == itemID }) else { return }

        processTapService.deactivate(itemID: itemID) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                if !result.success {
                    self.applyTapResult(result, enabling: false)
                    return
                }

                self.processTapService.activate(
                    itemID: itemID,
                    processObjectIDs: item.audioProcessObjectIDs,
                    outputDeviceUID: self.resolvedOutputDeviceUID(for: item),
                    volume: item.volume,
                    isMuted: item.isMuted,
                    boost: item.boost
                ) { [weak self] result in
                    Task { @MainActor in
                        self?.applyTapResult(result, enabling: true)
                    }
                }
            }
        }
    }

    private func deactivateProcessing(itemID: String) {
        processTapService.deactivate(itemID: itemID) { [weak self] result in
            Task { @MainActor in
                self?.applyTapResult(result, enabling: false)
            }
        }
    }

    private func resolvedOutputDeviceUID(for item: AudioAppVolumeItem) -> String? {
        if let outputDeviceUID = item.outputDeviceUID,
           outputDevices.contains(where: { $0.uid == outputDeviceUID }) {
            return outputDeviceUID
        }

        return defaultOutputDevice?.uid
    }

    private func applyTapResult(_ result: AudioProcessTapResult, enabling: Bool) {
        if result.success {
            if enabling {
                processingAppIDs.insert(result.itemID)
                lastMessage = String(localized: "Per-app audio processing is active.")
            } else {
                processingAppIDs.remove(result.itemID)
                lastMessage = nil
            }
            appItems = sortedAppItems(appItems)
            return
        }

        if applyPermissionFailureIfNeeded(result) {
            return
        }

        lastMessage = result.message
    }

    private func applyDeviceVolumeWrite(_ result: AudioControlWorker.DeviceVolumeWriteResult) {
        guard let index = outputDevices.firstIndex(where: { $0.id == result.deviceID }) else { return }

        if result.success {
            outputDevices[index].volume = result.value
            lastMessage = nil
            return
        }

        if let actualValue = result.actualValue {
            outputDevices[index].volume = actualValue
        }
        lastMessage = String(localized: "Output device volume is unavailable.")
    }

    private func synchronizeProcessing(
        previousItems: [String: AudioAppVolumeItem],
        currentItems: [AudioAppVolumeItem]
    ) {
        guard canControlAppAudio else { return }

        let currentItemsByID = Dictionary(
            currentItems.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )

        for itemID in Array(processingAppIDs) {
            guard let item = currentItemsByID[itemID],
                  item.isAudible,
                  !item.isIgnored else {
                deactivateProcessing(itemID: itemID)
                continue
            }

            guard let previous = previousItems[itemID] else { continue }
            if previous.audioProcessObjectIDs != item.audioProcessObjectIDs {
                restartProcessing(itemID: itemID)
            }
        }
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
            switch AudioCapturePermissionProbe.preflight() {
            case .authorized, .unknown:
                return .available
            case .denied:
                return .permissionRequired(String(localized: "Grant Screen & System Audio Recording permission to adjust per-app volume."))
            }
        }

        return .unsupported(String(localized: "Per-app volume requires macOS 14.4 or later."))
    }

    private func showAppAudioPermissionMessage() {
        lastMessage = captureSupport.message ?? String(localized: "Grant Screen & System Audio Recording permission to adjust per-app volume.")
    }

    private func applyPermissionFailureIfNeeded(_ result: AudioProcessTapResult) -> Bool {
        guard result.statusCode == kAudioDevicePermissionsError else {
            return false
        }

        let message = String(localized: "Grant Screen & System Audio Recording permission to adjust per-app volume.")
        captureSupport = .permissionRequired(message)
        lastMessage = message
        return true
    }
}

private enum AudioCapturePermissionStatus {
    case unknown
    case authorized
    case denied
}

private enum AudioCapturePermissionProbe {
    private static let tccServiceAudioCapture = "kTCCServiceAudioCapture" as CFString
    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int

    private static let tccHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    }()

    private static let preflightFunction: PreflightFunction? = {
        guard let tccHandle,
              let symbol = dlsym(tccHandle, "TCCAccessPreflight") else {
            return nil
        }

        return unsafeBitCast(symbol, to: PreflightFunction.self)
    }()

    static func preflight() -> AudioCapturePermissionStatus {
        guard let preflightFunction else {
            return .unknown
        }

        switch preflightFunction(tccServiceAudioCapture, nil) {
        case 0:
            return .authorized
        case 1:
            return .denied
        default:
            return .unknown
        }
    }
}

private final class AudioControlWorker {
    private let queue = DispatchQueue(label: "peakhalo.audio-control", qos: .userInitiated)
    private var pendingDeviceVolumeWrites: [AudioObjectID: Double] = [:]
    private var deviceVolumeTimers: [AudioObjectID: DispatchWorkItem] = [:]
    private let deviceVolumeDebounce: DispatchTimeInterval = .milliseconds(150)

    struct RefreshResult {
        let devices: [AudioOutputDevice]
        let audioProcesses: [AudioProcessInfo]
    }

    struct DeviceVolumeWriteResult {
        let deviceID: AudioObjectID
        let value: Double
        let success: Bool
        let actualValue: Double?
    }

    func refresh(
        service: SystemAudioVolumeService,
        processService: AudioProcessService,
        completion: @escaping (RefreshResult) -> Void
    ) {
        queue.async {
            completion(RefreshResult(
                devices: service.outputDevices(),
                audioProcesses: processService.audibleProcesses()
            ))
        }
    }

    func setDeviceVolume(
        _ value: Double,
        deviceID: AudioObjectID,
        service: SystemAudioVolumeService,
        completion: @escaping (DeviceVolumeWriteResult) -> Void
    ) {
        queue.async {
            self.pendingDeviceVolumeWrites[deviceID] = value
            self.deviceVolumeTimers[deviceID]?.cancel()

            let timer = DispatchWorkItem { [weak self, service] in
                guard let self,
                      let latestValue = self.pendingDeviceVolumeWrites.removeValue(forKey: deviceID) else {
                    return
                }
                self.deviceVolumeTimers.removeValue(forKey: deviceID)

                let success = service.setDeviceVolume(latestValue, deviceID: deviceID)
                let actualValue = success ? latestValue : service.outputDevices().first { $0.id == deviceID }?.volume
                completion(DeviceVolumeWriteResult(
                    deviceID: deviceID,
                    value: latestValue,
                    success: success,
                    actualValue: actualValue
                ))
            }
            self.deviceVolumeTimers[deviceID] = timer
            self.queue.asyncAfter(deadline: .now() + self.deviceVolumeDebounce, execute: timer)
        }
    }
}
