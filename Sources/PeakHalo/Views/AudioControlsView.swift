import AppKit
import SwiftUI

struct AudioControlsView: View {
    let compact: Bool
    @ObservedObject private var store = AudioControlStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                outputDeviceList
                sectionDivider
                appsHeader
                appList

                if let message = store.lastMessage {
                    Text(message)
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
            Text(store.isRefreshing ? "Scanning Audio" : "No output devices found.")
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
        Text("Apps")
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
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var appRows: some View {
        if store.appItems.isEmpty {
            Text("No running apps found.")
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

    private func permissionBanner(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "lock.shield")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: compact ? 16 : 18)

                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(primaryColor.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Open System Settings") {
                    openAudioPrivacySettings()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(controlProgressColor)

                Button("Check Again") {
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

        return HStack(spacing: compact ? 8 : 10) {
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
            .frame(width: compact ? 116 : 170, alignment: .leading)

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
                isEnabled: controlsEnabled,
                tint: controlProgressColor,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                onChange: { store.setAppVolume($0, itemID: item.id) }
            )
            .layoutPriority(1)

            boostMenu(item)
            playbackDeviceMenu(item)
            processingButton(item)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 45 : 50, maxHeight: compact ? 45 : 50)
        .contentShape(Rectangle())
        .contextMenu {
            Button(item.isPinned ? "Unpin App" : "Pin App") {
                store.togglePinned(itemID: item.id)
            }
            Button(item.isIgnored ? "Include App" : "Ignore App") {
                store.toggleIgnored(itemID: item.id)
            }
            Button("Open System Settings") {
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
        .help("Boost")
    }

    private func playbackDeviceMenu(_ item: AudioAppVolumeItem) -> some View {
        let controlsEnabled = store.canControlAppAudio && !item.isIgnored

        return Menu {
            Button {
                store.setAppOutputDevice(nil, itemID: item.id)
            } label: {
                Label("System Default", systemImage: item.outputDeviceUID == nil ? "checkmark" : "circle")
            }

            Divider()

            ForEach(store.outputDevices) { device in
                Button {
                    store.setAppOutputDevice(device.uid, itemID: item.id)
                } label: {
                    Label(device.name, systemImage: item.outputDeviceUID == device.uid ? "checkmark" : "circle")
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
                .foregroundStyle(item.outputDeviceUID == nil ? secondaryColor : .blue)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!controlsEnabled || store.outputDevices.isEmpty)
        .help("Playback Device")
    }

    private func processingButton(_ item: AudioAppVolumeItem) -> some View {
        let isEnabled = store.isProcessingEnabled(itemID: item.id)
        let controlsEnabled = store.canControlAppAudio && item.isAudible && !item.isIgnored

        return Button {
            store.toggleProcessing(itemID: item.id)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: compact ? 12 : 14, weight: .semibold))
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
        }
        .buttonStyle(.plain)
        .disabled(!controlsEnabled)
        .foregroundStyle(isEnabled ? .green : primaryColor.opacity(controlsEnabled ? 0.72 : 0.28))
        .fixedSize()
        .help(isEnabled ? "Disable Processing" : "Enable Processing")
    }

    private func iconButton(
        systemImage: String,
        isActive: Bool,
        isEnabled: Bool,
        activeColor: Color,
        help: LocalizedStringKey,
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
        .help(help)
    }

    private func openAudioPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func appStatusText(for item: AudioAppVolumeItem) -> String {
        guard store.canControlAppAudio else {
            return String(localized: "Authorization Required")
        }

        if item.isAudible {
            return store.isProcessingEnabled(itemID: item.id)
                ? String(localized: "Processing")
                : String(localized: "Playing")
        }

        if item.isRunning {
            return String(localized: "Running")
        }

        return String(localized: "Pinned")
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
    let isEnabled: Bool
    let tint: Color
    let primaryColor: Color
    let secondaryColor: Color
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 9) {
            ControlValueSlider(
                value: value,
                isEnabled: isEnabled,
                tint: tint,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                onChange: onChange
            )

            Text(isEnabled ? "\(Int(value.rounded()))%" : "--")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isEnabled ? primaryColor.opacity(0.72) : secondaryColor)
                .frame(width: 42, alignment: .trailing)
        }
    }
}
