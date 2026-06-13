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
    private let recordingPermission = AudioRecordingPermissionController.shared
    private let defaults: UserDefaults
    private var hasLoaded = false
    private var monitorTask: Task<Void, Never>?
    private var isProcessMonitoringActive = false
    private var pendingProcessingAppIDs = Set<String>()
    private var manuallyDisabledProcessingAppIDs = Set<String>()
    private var fallbackRoutedAppIDs = Set<String>()

    var defaultOutputDevice: AudioOutputDevice? {
        outputDevices.first { $0.isDefault }
    }

    var canControlAppAudio: Bool {
        captureSupport.allowsAppAudioControl
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refreshCaptureSupport()
    }

    func refreshIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func startMonitoring() {
        refreshCaptureSupport()
        requestAudioCapturePermissionIfNeeded()
        refreshIfNeeded()
        startProcessMonitoringIfPermitted()
        service.startDeviceMonitoring { [weak self] in
            guard let store = self else { return }
            Task { @MainActor in
                store.refresh()
            }
        }

        guard monitorTask == nil else { return }

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let store = self else { return }
                await MainActor.run {
                    store.refresh()
                }
            }
        }
    }

    func stopMonitoring() {
        service.stopDeviceMonitoring()
        processService.stopMonitoring()
        isProcessMonitoringActive = false
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
        worker.refresh(
            service: service,
            processService: processService,
            includeAudioProcesses: captureSupport.allowsAppAudioControl
        ) { [weak self] result in
            guard let store = self else { return }
            Task { @MainActor in
                let previousDefaultUID = store.defaultOutputDevice?.uid
                store.hasLoaded = true
                store.outputDevices = result.devices
                store.refreshAppItems(audioProcesses: result.audioProcesses)
                store.isRefreshing = false
                store.lastMessage = result.devices.isEmpty ? String(localized: "No output devices found.") : nil
                if store.defaultOutputDevice?.uid != previousDefaultUID {
                    store.routeDefaultFollowingApps()
                }
            }
        }
    }

    private func startProcessMonitoringIfPermitted() {
        guard captureSupport.allowsAppAudioControl, !isProcessMonitoringActive else { return }
        isProcessMonitoringActive = true
        processService.startMonitoring { [weak self] in
            guard let store = self else { return }
            Task { @MainActor in
                store.refresh()
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
        routeDefaultFollowingApps()
        refresh()
    }

    func setDeviceVolume(_ value: Double, deviceID: AudioObjectID) {
        guard let index = outputDevices.firstIndex(where: { $0.id == deviceID }),
              outputDevices[index].supportsVolume else {
            return
        }

        let clamped = Self.clamp(value)
        outputDevices[index].volume = clamped
        if outputDevices[index].supportsMute {
            outputDevices[index].isMuted = clamped <= 0
        }
        updateProcessingDeviceGainIfNeeded(for: outputDevices[index])

        worker.setDeviceVolume(
            clamped,
            deviceID: deviceID,
            service: service
        ) { [weak self] result in
            guard let store = self else { return }
            Task { @MainActor in
                store.applyDeviceVolumeWrite(result)
            }
        }
    }

    func setDeviceMuted(_ isMuted: Bool, deviceID: AudioObjectID) {
        guard let index = outputDevices.firstIndex(where: { $0.id == deviceID }),
              outputDevices[index].supportsMute else {
            return
        }

        outputDevices[index].isMuted = isMuted
        if isMuted {
            outputDevices[index].volume = 0
        }
        updateProcessingDeviceGainIfNeeded(for: outputDevices[index])

        worker.setDeviceMuted(
            isMuted,
            deviceID: deviceID,
            service: service
        ) { [weak self] result in
            guard let store = self else { return }
            Task { @MainActor in
                store.applyDeviceMuteWrite(result)
            }
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

    func setAppEqualizerEnabled(_ isEnabled: Bool, itemID: String) {
        guard canControlAppAudio else {
            showAppAudioPermissionMessage()
            return
        }

        updateAppItem(itemID) { item in
            item.equalizer.isEnabled = isEnabled
        }
        updateProcessingState(itemID: itemID)
    }

    func setAppEqualizerBand(_ index: Int, gain: Double, itemID: String) {
        guard canControlAppAudio else {
            showAppAudioPermissionMessage()
            return
        }

        guard index >= 0, index < AudioEqualizerSettings.bandCount else { return }
        updateAppItem(itemID) { item in
            item.equalizer.bandGains[index] = AudioEqualizerSettings.clampGain(gain)
            item.equalizer.isEnabled = true
        }
        updateProcessingState(itemID: itemID)
    }

    func applyAppEqualizerPreset(_ preset: AudioEqualizerPreset, itemID: String) {
        guard canControlAppAudio else {
            showAppAudioPermissionMessage()
            return
        }

        updateAppItem(itemID) { item in
            item.equalizer = preset.settings
        }
        updateProcessingState(itemID: itemID)
    }

    func setAppOutputDevice(_ outputDeviceUID: String?, itemID: String) {
        setAppOutputRoute(outputDeviceUID.map { .single($0) } ?? .systemDefault, itemID: itemID)
    }

    func setAppOutputRoute(_ routeIntent: AudioAppOutputRouteIntent, itemID: String) {
        guard canControlAppAudio else {
            showAppAudioPermissionMessage()
            return
        }

        updateAppItem(itemID) { item in
            item.outputRouteIntent = routeIntent
            item.outputDeviceUID = routeIntent.primaryOutputDeviceUID
        }

        manuallyDisabledProcessingAppIDs.remove(itemID)
        activateOrSwitchProcessing(itemID: itemID)
    }

    func toggleAppMultiOutputDevice(_ uid: String, itemID: String) {
        guard let item = appItems.first(where: { $0.id == itemID }) else { return }
        let baseIntent: AudioAppOutputRouteIntent = item.outputRouteIntent.isMulti
            ? item.outputRouteIntent
            : .multi(item.outputRouteIntent.selectedDeviceUIDs)
        setAppOutputRoute(baseIntent.togglingMultiDevice(uid), itemID: itemID)
    }

    func playbackDeviceTitle(for item: AudioAppVolumeItem) -> String {
        switch item.outputRouteIntent {
        case .systemDefault:
            return String(localized: "System Default")
        case .single(let uid):
            return outputDevices.first { $0.uid == uid }?.name ?? String(localized: "Unknown Output")
        case .multi(let uids):
            let names = uids.compactMap { uid in
                outputDevices.first { $0.uid == uid }?.name
            }
            guard !names.isEmpty else { return String(localized: "Unknown Outputs") }
            if names.count == 1 {
                return names[0]
            }
            return String.localizedStringWithFormat(String(localized: "%d Outputs"), names.count)
        }
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
            manuallyDisabledProcessingAppIDs.insert(itemID)
            pendingProcessingAppIDs.remove(itemID)
            deactivateProcessing(itemID: itemID)
            return
        }

        manuallyDisabledProcessingAppIDs.remove(itemID)
        activateOrSwitchProcessing(itemID: itemID)
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
        let nextStatus = recordingPermission.refreshStatus()
        let nextState = Self.captureSupport(for: nextStatus)
        captureSupport = nextState

        if !nextState.allowsAppAudioControl, !processingAppIDs.isEmpty {
            processTapService.deactivateAll()
            processingAppIDs.removeAll()
            appItems = sortedAppItems(appItems)
        }

        if !nextState.allowsAppAudioControl, isProcessMonitoringActive {
            processService.stopMonitoring()
            isProcessMonitoringActive = false
        }
    }

    private func updateAppItem(
        _ itemID: String,
        showSavedMessage: Bool = true,
        update: (inout AudioAppVolumeItem) -> Void
    ) {
        guard let index = appItems.firstIndex(where: { $0.id == itemID }) else { return }

        var item = appItems[index]
        update(&item)
        appItems[index] = item
        saveSettings(for: item)
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

        var existingIDs = Set(items.map(\.id))
        for app in runningApps {
            let id = storageID(for: app)
            guard !existingIDs.contains(id) else { continue }
            items.append(audioItem(for: app))
            existingIDs.insert(id)
        }

        let pinnedIDs = pinnedAppIDs()
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
                outputRouteIntent: settings.outputRouteIntent,
                equalizer: settings.equalizer,
                isPinned: settings.isPinned,
                isIgnored: settings.isIgnored
            ))
            existingIDs.insert(pinnedID)
        }

        appItems = sortedAppItems(items)
        synchronizeProcessing(previousItems: previousItems, currentItems: items)
        activatePendingProcessingIfPossible(currentItems: items)
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
        let representativeProcess = processes.first

        return AudioAppVolumeItem(
            id: id,
            name: app?.localizedName
                ?? app?.bundleIdentifier
                ?? representativeProcess?.displayName
                ?? representativeProcess?.bundleIdentifier
                ?? String(localized: "Audio Process"),
            bundleIdentifier: app?.bundleIdentifier ?? representativeProcess?.bundleIdentifier,
            processID: app?.processIdentifier ?? representativeProcess?.processID,
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
            boost: item.boost,
            deviceGain: deviceProcessingGain(for: item),
            equalizer: item.equalizer
        )
    }

    private func restartProcessing(itemID: String) {
        guard canControlAppAudio else { return }
        guard let item = appItems.first(where: { $0.id == itemID }) else { return }

        processTapService.deactivate(itemID: itemID) { [weak self] result in
            guard let store = self else { return }
            Task { @MainActor in
                if !result.success {
                    store.applyTapResult(result, enabling: false)
                    return
                }

                store.processTapService.activate(
                    itemID: itemID,
                    processObjectIDs: item.audioProcessObjectIDs,
                    route: store.resolvedRoute(for: item),
                    volume: item.volume,
                    isMuted: item.isMuted,
                    boost: item.boost,
                    deviceGain: store.deviceProcessingGain(for: item),
                    equalizer: item.equalizer
                ) { [weak self] result in
                    guard let store = self else { return }
                    Task { @MainActor in
                        store.applyTapResult(result, enabling: true)
                    }
                }
            }
        }
    }

    private func activateOrSwitchProcessing(itemID: String) {
        guard canControlAppAudio else { return }
        guard let item = appItems.first(where: { $0.id == itemID }),
              !item.isIgnored else {
            return
        }

        guard !item.audioProcessObjectIDs.isEmpty else {
            pendingProcessingAppIDs.insert(itemID)
            lastMessage = String(localized: "No active audio process is available for this app.")
            return
        }

        processTapService.switchOutputDevice(
            itemID: itemID,
            processObjectIDs: item.audioProcessObjectIDs,
            route: resolvedRoute(for: item),
            volume: item.volume,
            isMuted: item.isMuted,
            boost: item.boost,
            deviceGain: deviceProcessingGain(for: item),
            equalizer: item.equalizer
        ) { [weak self] result in
            guard let store = self else { return }
            Task { @MainActor in
                store.applyTapResult(result, enabling: true)
            }
        }
    }

    private func routeDefaultFollowingApps() {
        guard canControlAppAudio, defaultOutputDevice?.uid != nil else { return }

        for item in appItems
            where item.outputRouteIntent == .systemDefault
                && processingAppIDs.contains(item.id)
                && !item.audioProcessObjectIDs.isEmpty {
            processTapService.switchOutputDevice(
                itemID: item.id,
                processObjectIDs: item.audioProcessObjectIDs,
                route: resolvedRoute(for: item),
                volume: item.volume,
                isMuted: item.isMuted,
                boost: item.boost,
                deviceGain: deviceProcessingGain(for: item),
                equalizer: item.equalizer
            ) { [weak self] result in
                guard let store = self else { return }
                Task { @MainActor in
                    store.applyTapResult(result, enabling: true)
                }
            }
        }
    }

    private func activatePendingProcessingIfPossible(currentItems: [AudioAppVolumeItem]) {
        guard canControlAppAudio, !pendingProcessingAppIDs.isEmpty else { return }

        for item in currentItems
            where pendingProcessingAppIDs.contains(item.id)
                && !manuallyDisabledProcessingAppIDs.contains(item.id)
                && !item.isIgnored
                && !item.audioProcessObjectIDs.isEmpty {
            activateOrSwitchProcessing(itemID: item.id)
        }
    }

    private func deactivateProcessing(itemID: String) {
        processTapService.deactivate(itemID: itemID) { [weak self] result in
            guard let store = self else { return }
            Task { @MainActor in
                store.applyTapResult(result, enabling: false)
            }
        }
    }

    private func deviceProcessingGain(for item: AudioAppVolumeItem) -> Double {
        switch item.outputRouteIntent {
        case .systemDefault:
            return defaultOutputDevice?.softwareProcessingGain ?? 1
        case .single(let outputDeviceUID):
            let device = outputDevices.first { $0.uid == outputDeviceUID } ?? defaultOutputDevice
            return device?.softwareProcessingGain ?? 1
        case .multi:
            return 1
        }
    }

    private func updateProcessingDeviceGainIfNeeded(for device: AudioOutputDevice) {
        guard device.volumeBackend == .software,
              canControlAppAudio,
              !processingAppIDs.isEmpty else {
            return
        }

        for item in appItems
            where processingAppIDs.contains(item.id)
                && itemUsesSoftwareDeviceGain(item, deviceUID: device.uid) {
            processTapService.update(
                itemID: item.id,
                volume: item.volume,
                isMuted: item.isMuted,
                boost: item.boost,
                deviceGain: deviceProcessingGain(for: item),
                equalizer: item.equalizer
            )
        }
    }

    private func itemUsesSoftwareDeviceGain(_ item: AudioAppVolumeItem, deviceUID: String) -> Bool {
        switch item.outputRouteIntent {
        case .systemDefault:
            return defaultOutputDevice?.uid == deviceUID
        case .single(let outputDeviceUID):
            if outputDevices.contains(where: { $0.uid == outputDeviceUID }) {
                return outputDeviceUID == deviceUID
            }
            return defaultOutputDevice?.uid == deviceUID
        case .multi:
            return false
        }
    }

    private func resolvedRoute(for item: AudioAppVolumeItem) -> AudioProcessTapRoute? {
        switch item.outputRouteIntent {
        case .single(let outputDeviceUID):
            if let device = outputDevices.first(where: { $0.uid == outputDeviceUID }) {
                fallbackRoutedAppIDs.remove(item.id)
                return AudioProcessTapRoute(
                    outputDeviceID: device.id,
                    outputDeviceUID: device.uid,
                    outputDevices: [device],
                    followsSystemDefault: false,
                    preferredTapSourceDeviceUID: nil
                )
            }

            if let defaultOutputDevice {
                fallbackRoutedAppIDs.insert(item.id)
                return AudioProcessTapRoute(
                    outputDeviceID: defaultOutputDevice.id,
                    outputDeviceUID: defaultOutputDevice.uid,
                    outputDevices: [defaultOutputDevice],
                    followsSystemDefault: false,
                    preferredTapSourceDeviceUID: nil
                )
            }

            return nil
        case .multi(let outputDeviceUIDs):
            let selectedDevices = outputDeviceUIDs.compactMap { uid in
                outputDevices.first { $0.uid == uid }
            }
            if let firstDevice = selectedDevices.first {
                fallbackRoutedAppIDs.remove(item.id)
                return AudioProcessTapRoute(
                    outputDeviceID: firstDevice.id,
                    outputDeviceUID: firstDevice.uid,
                    outputDevices: selectedDevices,
                    followsSystemDefault: false,
                    preferredTapSourceDeviceUID: nil
                )
            }

            if let defaultOutputDevice {
                fallbackRoutedAppIDs.insert(item.id)
                return AudioProcessTapRoute(
                    outputDeviceID: defaultOutputDevice.id,
                    outputDeviceUID: defaultOutputDevice.uid,
                    outputDevices: [defaultOutputDevice],
                    followsSystemDefault: false,
                    preferredTapSourceDeviceUID: nil
                )
            }

            return nil
        case .systemDefault:
            fallbackRoutedAppIDs.remove(item.id)
            guard let defaultOutputDevice else { return nil }
            return AudioProcessTapRoute(
                outputDeviceID: defaultOutputDevice.id,
                outputDeviceUID: defaultOutputDevice.uid,
                outputDevices: [defaultOutputDevice],
                followsSystemDefault: true,
                preferredTapSourceDeviceUID: defaultOutputDevice.uid
            )
        }
    }

    private func applyTapResult(_ result: AudioProcessTapResult, enabling: Bool) {
        if result.success {
            if enabling {
                processingAppIDs.insert(result.itemID)
                pendingProcessingAppIDs.remove(result.itemID)
                manuallyDisabledProcessingAppIDs.remove(result.itemID)
                if fallbackRoutedAppIDs.remove(result.itemID) != nil {
                    lastMessage = String(localized: "Selected output is unavailable. Using System Default.")
                } else {
                    lastMessage = String(localized: "Per-app audio processing is active.")
                }
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
            outputDevices[index].volume = result.actualValue ?? result.value
            if outputDevices[index].supportsMute {
                outputDevices[index].isMuted = result.actualIsMuted ?? (outputDevices[index].volume <= 0)
            }
            updateProcessingDeviceGainIfNeeded(for: outputDevices[index])
            lastMessage = nil
            return
        }

        if let actualValue = result.actualValue {
            outputDevices[index].volume = actualValue
        }
        updateProcessingDeviceGainIfNeeded(for: outputDevices[index])
        lastMessage = String(localized: "Output device volume is unavailable.")
    }

    private func applyDeviceMuteWrite(_ result: AudioControlWorker.DeviceMuteWriteResult) {
        guard let index = outputDevices.firstIndex(where: { $0.id == result.deviceID }) else { return }

        if result.success {
            if let actualValue = result.actualValue {
                outputDevices[index].volume = actualValue
            }
            outputDevices[index].isMuted = result.actualIsMuted ?? result.isMuted
            updateProcessingDeviceGainIfNeeded(for: outputDevices[index])
            lastMessage = nil
            return
        }

        if let actualValue = result.actualValue {
            outputDevices[index].volume = actualValue
        }
        outputDevices[index].isMuted = result.actualIsMuted ?? !result.isMuted
        updateProcessingDeviceGainIfNeeded(for: outputDevices[index])
        lastMessage = String(localized: "Output device mute is unavailable.")
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

    private static func captureSupport(for status: AudioRecordingPermissionStatus) -> AudioCaptureSupportState {
        switch status {
        case .authorized:
            return .available
        case .unknown:
            return .permissionRequired(String(localized: "Allow Screen & System Audio Recording to adjust per-app volume."))
        case .denied:
            return .permissionRequired(String(localized: "Grant Screen & System Audio Recording permission to adjust per-app volume."))
        case .unsupported:
            break
        }

        return .unsupported(String(localized: "Per-app volume requires macOS 14.4 or later."))
    }

    private func showAppAudioPermissionMessage() {
        requestAudioCapturePermissionIfNeeded()
        lastMessage = captureSupport.message ?? String(localized: "Grant Screen & System Audio Recording permission to adjust per-app volume.")
    }

    private func requestAudioCapturePermissionIfNeeded() {
        recordingPermission.requestIfNeeded { [weak self] status in
            guard let self else { return }
            self.captureSupport = Self.captureSupport(for: status)
            if self.captureSupport.allowsAppAudioControl {
                self.startProcessMonitoringIfPermitted()
                self.lastMessage = nil
                self.refresh()
            } else {
                self.lastMessage = self.captureSupport.message
            }
        }
    }

    private func applyPermissionFailureIfNeeded(_ result: AudioProcessTapResult) -> Bool {
        guard result.statusCode == kAudioDevicePermissionsError else {
            return false
        }

        let message = String(localized: "Grant Screen & System Audio Recording permission to adjust per-app volume.")
        recordingPermission.markDenied()
        captureSupport = .permissionRequired(message)
        lastMessage = message
        return true
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
        let actualIsMuted: Bool?
    }

    struct DeviceMuteWriteResult {
        let deviceID: AudioObjectID
        let isMuted: Bool
        let success: Bool
        let actualValue: Double?
        let actualIsMuted: Bool?
    }

    func refresh(
        service: SystemAudioVolumeService,
        processService: AudioProcessService,
        includeAudioProcesses: Bool,
        completion: @escaping (RefreshResult) -> Void
    ) {
        queue.async {
            completion(RefreshResult(
                devices: service.outputDevices(),
                audioProcesses: includeAudioProcesses ? processService.audibleProcesses() : []
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
            if let pendingValue = self.pendingDeviceVolumeWrites[deviceID],
               abs(pendingValue - value) < 0.05 {
                return
            }

            self.pendingDeviceVolumeWrites[deviceID] = value
            self.deviceVolumeTimers[deviceID]?.cancel()

            let timer = DispatchWorkItem { [weak self, service] in
                guard let self,
                      let latestValue = self.pendingDeviceVolumeWrites.removeValue(forKey: deviceID) else {
                    return
                }
                self.deviceVolumeTimers.removeValue(forKey: deviceID)

                let write = service.setDeviceVolumeAndReadState(latestValue, deviceID: deviceID)
                completion(DeviceVolumeWriteResult(
                    deviceID: deviceID,
                    value: latestValue,
                    success: write.success,
                    actualValue: write.actualVolume ?? (write.success ? latestValue : nil),
                    actualIsMuted: write.actualIsMuted
                ))
            }
            self.deviceVolumeTimers[deviceID] = timer
            self.queue.asyncAfter(deadline: .now() + self.deviceVolumeDebounce, execute: timer)
        }
    }

    func setDeviceMuted(
        _ isMuted: Bool,
        deviceID: AudioObjectID,
        service: SystemAudioVolumeService,
        completion: @escaping (DeviceMuteWriteResult) -> Void
    ) {
        queue.async {
            self.deviceVolumeTimers[deviceID]?.cancel()
            self.deviceVolumeTimers.removeValue(forKey: deviceID)
            self.pendingDeviceVolumeWrites.removeValue(forKey: deviceID)

            let write = service.setDeviceMutedAndReadState(isMuted, deviceID: deviceID)
            completion(DeviceMuteWriteResult(
                deviceID: deviceID,
                isMuted: isMuted,
                success: write.success,
                actualValue: write.actualVolume,
                actualIsMuted: write.actualIsMuted
            ))
        }
    }
}
