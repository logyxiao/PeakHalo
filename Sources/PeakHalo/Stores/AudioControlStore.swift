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
    @Published private(set) var lastMessage: LocalizedMessage?
    @Published private(set) var captureSupport: AudioCaptureSupportState = .available

    private let service = SystemAudioVolumeService()
    private let processService = AudioProcessService()
    private let processTapService = AudioProcessTapService()
    private let worker = AudioControlWorker()
    private let recordingPermission = AudioRecordingPermissionController.shared
    private let appSettingsStore: AudioAppSettingsStore
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
        self.appSettingsStore = AudioAppSettingsStore(defaults: defaults)
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
                store.lastMessage = result.devices.isEmpty ? .string("No output devices found.") : nil
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
            lastMessage = .string("Could not switch output device.")
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

        if isMuted, !processingAppIDs.contains(itemID) {
            manuallyDisabledProcessingAppIDs.remove(itemID)
            activateOrSwitchProcessing(itemID: itemID)
        } else {
            updateProcessingState(itemID: itemID)
        }
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
            return AppLanguageStore.shared.localizedString("System Default")
        case .single(let uid):
            return outputDevices.first { $0.uid == uid }?.name ?? AppLanguageStore.shared.localizedString("Unknown Output")
        case .multi(let uids):
            let names = uids.compactMap { uid in
                outputDevices.first { $0.uid == uid }?.name
            }
            guard !names.isEmpty else { return AppLanguageStore.shared.localizedString("Unknown Outputs") }
            if names.count == 1 {
                return names[0]
            }
            return AppLanguageStore.shared.localizedString("%d Outputs", arguments: [.int(names.count)])
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
        applyCaptureSupportStatus(recordingPermission.refreshStatus())
    }

    func recheckAudioCapturePermission() {
        recordingPermission.recheckFromSettings { [weak self] status in
            guard let self else { return }
            self.applyCaptureSupportStatus(status)
            if self.captureSupport.allowsAppAudioControl {
                self.startProcessMonitoringIfPermitted()
                self.lastMessage = nil
                self.refresh()
            } else {
                self.lastMessage = self.captureSupport.message
            }
        }
    }

    private func applyCaptureSupportStatus(_ status: AudioRecordingPermissionStatus) {
        let nextState = Self.captureSupport(for: status)
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
        appSettingsStore.saveSettings(for: item)
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
            .map {
                RunningAudioAppDescriptor(
                    processID: $0.processIdentifier,
                    bundleIdentifier: $0.bundleIdentifier,
                    localizedName: $0.localizedName,
                    icon: $0.icon
                )
            }

        let result = AudioAppItemBuilder.buildItems(
            audioProcesses: audioProcesses,
            runningApps: runningApps,
            settingsStore: appSettingsStore,
            audioProcessFallbackName: AppLanguageStore.shared.localizedString("Audio Process"),
            pinnedFallbackName: AppLanguageStore.shared.localizedString("Pinned App")
        )

        appItems = sortedAppItems(result.items)
        applyProcessingPlan(previousItems: previousItems, currentItems: result.items)
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
            lastMessage = .string("No active audio process is available for this app.")
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


    private func deactivateProcessing(itemID: String) {
        processTapService.deactivate(itemID: itemID) { [weak self] result in
            guard let store = self else { return }
            Task { @MainActor in
                store.applyTapResult(result, enabling: false)
            }
        }
    }

    private func deviceProcessingGain(for item: AudioAppVolumeItem) -> Double {
        AudioRouteResolver.processingGain(
            for: item,
            outputDevices: outputDevices,
            defaultOutputDevice: defaultOutputDevice
        )
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
        AudioRouteResolver.itemUsesSoftwareDeviceGain(
            item,
            deviceUID: deviceUID,
            outputDevices: outputDevices,
            defaultOutputDevice: defaultOutputDevice
        )
    }

    private func resolvedRoute(for item: AudioAppVolumeItem) -> AudioProcessTapRoute? {
        guard let resolution = AudioRouteResolver.resolve(
            for: item,
            outputDevices: outputDevices,
            defaultOutputDevice: defaultOutputDevice
        ) else {
            return nil
        }

        if resolution.usedFallback {
            fallbackRoutedAppIDs.insert(item.id)
        } else {
            fallbackRoutedAppIDs.remove(item.id)
        }

        return resolution.route
    }

    private func applyTapResult(_ result: AudioProcessTapResult, enabling: Bool) {
        let reduction = AudioTapResultReducer.reduce(
            result: result,
            enabling: enabling,
            state: AudioTapResultState(
                processingItemIDs: processingAppIDs,
                pendingItemIDs: pendingProcessingAppIDs,
                manuallyDisabledItemIDs: manuallyDisabledProcessingAppIDs,
                fallbackRoutedItemIDs: fallbackRoutedAppIDs
            )
        )

        processingAppIDs = reduction.state.processingItemIDs
        pendingProcessingAppIDs = reduction.state.pendingItemIDs
        manuallyDisabledProcessingAppIDs = reduction.state.manuallyDisabledItemIDs
        fallbackRoutedAppIDs = reduction.state.fallbackRoutedItemIDs
        lastMessage = reduction.message

        if reduction.permissionDenied {
            recordingPermission.markDenied()
            captureSupport = .permissionRequired(reduction.message ?? .string("Grant Screen & System Audio Recording permission to adjust per-app volume."))
        }

        if reduction.shouldResortItems {
            appItems = sortedAppItems(appItems)
        }
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
        lastMessage = .string("Output device volume is unavailable.")
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
        lastMessage = .string("Output device mute is unavailable.")
    }

    private func applyProcessingPlan(
        previousItems: [String: AudioAppVolumeItem],
        currentItems: [AudioAppVolumeItem]
    ) {
        guard canControlAppAudio else { return }

        let plan = AudioProcessingPlanner.plan(
            processingItemIDs: processingAppIDs,
            pendingItemIDs: pendingProcessingAppIDs,
            manuallyDisabledItemIDs: manuallyDisabledProcessingAppIDs,
            previousItems: previousItems,
            currentItems: currentItems
        )

        for itemID in plan.deactivateItemIDs {
            deactivateProcessing(itemID: itemID)
        }
        for itemID in plan.restartItemIDs {
            restartProcessing(itemID: itemID)
        }
        for itemID in plan.activatePendingItemIDs {
            activateOrSwitchProcessing(itemID: itemID)
        }
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
            return .permissionRequired(.string("Allow Screen & System Audio Recording to adjust per-app volume."))
        case .denied:
            return .permissionRequired(.string("Grant Screen & System Audio Recording permission to adjust per-app volume."))
        case .unsupported:
            break
        }

        return .unsupported(.string("Per-app volume requires macOS 14.4 or later."))
    }

    private func showAppAudioPermissionMessage() {
        requestAudioCapturePermissionIfNeeded()
        lastMessage = captureSupport.message ?? .string("Grant Screen & System Audio Recording permission to adjust per-app volume.")
    }

    private func requestAudioCapturePermissionIfNeeded() {
        recordingPermission.requestIfNeeded { [weak self] status in
            guard let self else { return }
            self.applyCaptureSupportStatus(status)
            if self.captureSupport.allowsAppAudioControl {
                self.startProcessMonitoringIfPermitted()
                self.lastMessage = nil
                self.refresh()
            } else {
                self.lastMessage = self.captureSupport.message
            }
        }
    }

}
