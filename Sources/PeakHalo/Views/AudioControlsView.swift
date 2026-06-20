import AppKit
import SwiftUI

struct AudioControlsView: View {
    let compact: Bool
    @ObservedObject private var store = AudioControlStore.shared
    @ObservedObject private var languageStore = AppLanguageStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var playbackPickerItemID: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                outputDeviceList
                sectionDivider
                appsHeader
                appList

                if let message = store.lastMessage {
                    Text(languageStore.localizedString(message))
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(2)
                        .padding(.top, 6)
                }
            }
            .padding(.horizontal, compact ? 4 : 0)
            .padding(.vertical, compact ? 2 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: compact ? 246 : nil, alignment: .topLeading)
        .onAppear {
            store.startMonitoring()
        }
        .onDisappear {
            store.stopMonitoring()
        }
    }

    @ViewBuilder
    private var outputDeviceList: some View {
        if store.outputDevices.isEmpty {
            Text(languageStore.localizedString(store.isRefreshing ? "Scanning Audio" : "No output devices found."))
                .font(compact ? .caption : .callout)
                .foregroundStyle(secondaryColor)
                .frame(maxWidth: .infinity, minHeight: compact ? 64 : 110, alignment: .center)
        } else {
            VStack(spacing: compact ? 3 : 5) {
                ForEach(store.outputDevices.prefix(compact ? 4 : 8)) { device in
                    outputDeviceRow(device)
                }
            }
        }
    }

    private func outputDeviceRow(_ device: AudioOutputDevice) -> some View {
        HStack(spacing: compact ? 9 : 12) {
            Button {
                if !device.isDefault {
                    store.setDefaultOutputDevice(device.id)
                }
            } label: {
                HStack(spacing: compact ? 8 : 10) {
                    Circle()
                        .fill(device.isDefault ? Color.blue : Color.white.opacity(0.12))
                        .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                        .overlay {
                            Image(systemName: deviceIconName(for: device))
                                .font(.system(size: compact ? 15 : 17, weight: .semibold))
                                .foregroundStyle(device.isDefault ? .white : secondaryColor)
                        }

                    Text(device.name)
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .frame(width: compact ? 176 : 230, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .help(device.isDefault ? "Default Output" : "Set as Output")

            iconButton(
                systemImage: device.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isActive: device.isMuted,
                isEnabled: device.supportsMute,
                activeColor: .red,
                help: device.isMuted ? "Unmute" : "Mute"
            ) {
                store.setDeviceMuted(!device.isMuted, deviceID: device.id)
            }

            AudioSlider(
                value: device.volume,
                volumeBackend: device.volumeBackend,
                isEnabled: device.supportsVolume,
                tint: controlProgressColor,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                onChange: { store.setDeviceVolume($0, deviceID: device.id) }
            )
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 39 : 44, maxHeight: compact ? 39 : 44)
        .contentShape(Rectangle())
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(compact ? 0.16 : 0.12))
            .frame(height: 1)
            .padding(.vertical, compact ? 8 : 12)
    }

    private var appsHeader: some View {
        Text(languageStore.localizedString("Apps"))
            .font(.system(size: compact ? 11 : 12, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(secondaryColor)
            .padding(.bottom, compact ? 5 : 8)
    }

    @ViewBuilder
    private var appList: some View {
        switch store.captureSupport {
        case .available:
            appRows
        case .permissionRequired(let reason):
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                permissionBanner(reason)
                appRows
            }
        case .unsupported(let reason):
            Text(languageStore.localizedString(reason))
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var appRows: some View {
        if store.appItems.isEmpty {
            Text(languageStore.localizedString("No running apps found."))
                .font(.caption)
                .foregroundStyle(secondaryColor)
                .frame(maxWidth: .infinity, minHeight: compact ? 50 : 80, alignment: .center)
        } else {
            VStack(spacing: compact ? 4 : 6) {
                ForEach(store.appItems.prefix(compact ? 4 : 12)) { item in
                    appVolumeRow(item)
                }
            }
        }
    }

    private func permissionBanner(_ reason: LocalizedMessage) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "lock.shield")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: compact ? 16 : 18)

                Text(languageStore.localizedString(reason))
                    .font(.caption2)
                    .foregroundStyle(primaryColor.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(languageStore.localizedString("Open System Settings")) {
                    openAudioPrivacySettings()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(controlProgressColor)

                Button(languageStore.localizedString("Check Again")) {
                    store.refreshCaptureSupport()
                    store.refresh()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(controlProgressColor)
            }
        }
        .padding(compact ? 7 : 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(primaryColor.opacity(compact ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func appVolumeRow(_ item: AudioAppVolumeItem) -> some View {
        let controlsEnabled = store.canControlAppAudio && !item.isIgnored

        return VStack(spacing: compact ? 5 : 7) {
            HStack(spacing: compact ? 8 : 10) {
                appIcon(item.icon)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .foregroundStyle(item.isIgnored ? secondaryColor : primaryColor)
                        .lineLimit(1)

                    Text(appSubtitle(for: item))
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }
                .frame(width: compact ? 96 : 150, alignment: .leading)

                playbackDeviceMenu(item)

                iconButton(
                    systemImage: item.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    isActive: item.isMuted,
                    isEnabled: controlsEnabled,
                    activeColor: .red,
                    help: item.isMuted ? "Unmute App" : "Mute App"
                ) {
                    store.setAppMuted(!item.isMuted, itemID: item.id)
                }

                AudioSlider(
                    value: item.volume,
                    volumeBackend: .software,
                    isEnabled: controlsEnabled,
                    tint: controlProgressColor,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    onChange: { store.setAppVolume($0, itemID: item.id) }
                )
                .layoutPriority(1)

                boostMenu(item)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 45 : 50, maxHeight: compact ? 45 : 50)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .contextMenu {
            Button(languageStore.localizedString(item.isPinned ? "Unpin App" : "Pin App")) {
                store.togglePinned(itemID: item.id)
            }
            Button(languageStore.localizedString(item.isIgnored ? "Include App" : "Ignore App")) {
                store.toggleIgnored(itemID: item.id)
            }
            Button(languageStore.localizedString("Open System Settings")) {
                openAudioPrivacySettings()
            }
        }
    }

    private func boostMenu(_ item: AudioAppVolumeItem) -> some View {
        let controlsEnabled = store.canControlAppAudio && !item.isIgnored

        return Menu {
            ForEach(AudioBoostLevel.allCases) { level in
                Button {
                    store.setAppBoost(level, itemID: item.id)
                } label: {
                    Label(level.title, systemImage: item.boost == level ? "checkmark" : "circle")
                }
            }
        } label: {
            Image(systemName: "chevron.up.2")
                .font(.system(size: compact ? 12 : 14, weight: .bold))
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
                .foregroundStyle(item.boost == .x1 ? secondaryColor : .blue)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!controlsEnabled)
        .help(languageStore.localizedString("Boost"))
    }

    private func playbackDeviceMenu(_ item: AudioAppVolumeItem) -> some View {
        let controlsEnabled = store.canControlAppAudio && !item.isIgnored
        let isPresented = Binding(
            get: { playbackPickerItemID == item.id },
            set: { isPresented in
                if !isPresented {
                    playbackPickerItemID = nil
                }
            }
        )

        return Button {
            playbackPickerItemID = item.id
        } label: {
            Image(systemName: "globe")
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .frame(width: compact ? 24 : 26, height: compact ? 24 : 26)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(playbackPickerItemID == item.id || item.outputRouteIntent != .systemDefault
                            ? Color.blue.opacity(0.16)
                            : Color.clear)
                }
                .foregroundStyle(item.outputRouteIntent == .systemDefault ? secondaryColor : .blue)
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            PlaybackDevicePickerView(
                item: item,
                devices: store.outputDevices,
                compact: compact,
                deviceIconName: deviceIconName(for:),
                onSelectRoute: { routeIntent in
                    store.setAppOutputRoute(routeIntent, itemID: item.id)
                    if !routeIntent.isMulti {
                        playbackPickerItemID = nil
                    }
                },
                onToggleMultiDevice: { uid in
                    store.toggleAppMultiOutputDevice(uid, itemID: item.id)
                }
            )
        }
        .fixedSize()
        .disabled(!controlsEnabled || store.outputDevices.isEmpty)
        .help(languageStore.localizedString("Playback Device"))
    }

    private func iconButton(
        systemImage: String,
        isActive: Bool,
        isEnabled: Bool,
        activeColor: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isActive ? activeColor : primaryColor.opacity(isEnabled ? 0.58 : 0.24))
        .help(languageStore.localizedString(help))
    }

    private func openAudioPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func appStatusText(for item: AudioAppVolumeItem) -> String {
        guard store.canControlAppAudio else {
            return languageStore.localizedString("Authorization Required")
        }

        if item.isAudible {
            return store.isProcessingEnabled(itemID: item.id)
                ? languageStore.localizedString("Processing")
                : languageStore.localizedString("Playing")
        }

        if item.isRunning {
            return languageStore.localizedString("Running")
        }

        return languageStore.localizedString("Pinned")
    }

    private func appSubtitle(for item: AudioAppVolumeItem) -> String {
        "\(appStatusText(for: item)) - \(store.playbackDeviceTitle(for: item))"
    }

    private func deviceIconName(for device: AudioOutputDevice) -> String {
        let value = "\(device.name) \(device.transportName)".lowercased()

        if value.contains("bluetooth") || value.contains("airpods") || value.contains("headphone") || value.contains("huawei") {
            return "headphones"
        }

        if value.contains("macbook") || value.contains("built") {
            return "laptopcomputer"
        }

        if value.contains("display") || value.contains("hdmi") || value.contains("displayport") {
            return "display"
        }

        return "speaker.wave.2"
    }

    @ViewBuilder
    private func appIcon(_ icon: NSImage?) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.10))
                .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                .overlay {
                    Image(systemName: "app")
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .foregroundStyle(secondaryColor)
                }
        }
    }

    private var primaryColor: Color {
        compact ? .white : .primary
    }

    private var secondaryColor: Color {
        compact ? .white.opacity(0.56) : .secondary
    }

    private var controlProgressColor: Color {
        colorScheme == .dark
            ? Color(red: 0.38, green: 0.80, blue: 1.0)
            : Color(red: 0.02, green: 0.48, blue: 0.88)
    }
}

private struct AudioSlider: View {
    let value: Double
    let volumeBackend: AudioOutputVolumeBackend
    let isEnabled: Bool
    let tint: Color
    let primaryColor: Color
    let secondaryColor: Color
    let onChange: (Double) -> Void

    private var sliderValue: Double {
        AudioVolumeMapping.sliderPercent(forGainPercent: value, backend: volumeBackend)
    }

    var body: some View {
        HStack(spacing: 9) {
            ControlValueSlider(
                value: sliderValue,
                isEnabled: isEnabled,
                tint: tint,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                onChange: { sliderPercent in
                    onChange(AudioVolumeMapping.gainPercent(forSliderPercent: sliderPercent, backend: volumeBackend))
                }
            )

            Text(isEnabled ? "\(Int(sliderValue.rounded()))%" : "--")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isEnabled ? primaryColor.opacity(0.72) : secondaryColor)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

private struct PlaybackDevicePickerView: View {
    @ObservedObject private var languageStore = AppLanguageStore.shared
    let item: AudioAppVolumeItem
    let devices: [AudioOutputDevice]
    let compact: Bool
    let deviceIconName: (AudioOutputDevice) -> String
    let onSelectRoute: (AudioAppOutputRouteIntent) -> Void
    let onToggleMultiDevice: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            modeSegments

            Divider()
                .padding(.top, 7)

            VStack(spacing: compact ? 2 : 4) {
                if !item.outputRouteIntent.isMulti {
                    pickerRow(
                        title: languageStore.localizedString("System Audio"),
                        subtitle: languageStore.localizedString("Follows macOS default"),
                        systemImage: "globe",
                        isSelected: item.outputRouteIntent == .systemDefault,
                        action: { onSelectRoute(.systemDefault) }
                    )
                }

                ForEach(devices) { device in
                    pickerRow(
                        title: device.name,
                        subtitle: nil,
                        systemImage: deviceIconName(device),
                        isSelected: isSelected(device.uid),
                        trailingSystemImage: device.isDefault ? "star.fill" : nil,
                        action: {
                            if item.outputRouteIntent.isMulti {
                                onToggleMultiDevice(device.uid)
                            } else {
                                onSelectRoute(.single(device.uid))
                            }
                        }
                    )
                }
            }
            .padding(.top, 8)
        }
        .padding(10)
        .frame(width: compact ? 300 : 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var modeSegments: some View {
        HStack(spacing: 0) {
            modeSegment(
                title: languageStore.localizedString("Single"),
                isSelected: !item.outputRouteIntent.isMulti,
                action: {
                    onSelectRoute(singleRouteAfterLeavingMulti())
                }
            )

            modeSegment(
                title: languageStore.localizedString("Multi"),
                isSelected: item.outputRouteIntent.isMulti,
                action: {
                    onSelectRoute(multiRouteAfterEnteringMulti())
                }
            )
        }
        .padding(3)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func modeSegment(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .blue : .secondary.opacity(0.5))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.18))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ uid: String) -> Bool {
        switch item.outputRouteIntent {
        case .systemDefault:
            return false
        case .single(let selectedUID):
            return selectedUID == uid
        case .multi(let selectedUIDs):
            return selectedUIDs.contains(uid)
        }
    }

    private func singleRouteAfterLeavingMulti() -> AudioAppOutputRouteIntent {
        if let uid = item.outputRouteIntent.selectedDeviceUIDs.first {
            return .single(uid)
        }

        return .systemDefault
    }

    private func multiRouteAfterEnteringMulti() -> AudioAppOutputRouteIntent {
        let selectedUIDs = item.outputRouteIntent.selectedDeviceUIDs
        if !selectedUIDs.isEmpty {
            return .multi(selectedUIDs)
        }

        if let defaultUID = devices.first(where: { $0.isDefault })?.uid {
            return .multi([defaultUID])
        }

        if let firstUID = devices.first?.uid {
            return .multi([firstUID])
        }

        return .systemDefault
    }

    private func pickerRow(
        title: String,
        subtitle: String?,
        systemImage: String,
        isSelected: Bool,
        trailingSystemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark" : "")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 18)

                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.62))
                        .frame(width: 18)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: subtitle == nil ? 36 : 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
