import AppKit
import SwiftUI

struct AudioControlsView: View {
    let compact: Bool
    @ObservedObject private var store = AudioControlStore.shared

    private var defaultDevice: AudioOutputDevice? {
        store.defaultOutputDevice
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                    defaultOutputCard
                    outputDevicesSection
                    appVolumeSection
                }
            }
            .frame(maxHeight: compact ? 230 : nil)

            if let message = store.lastMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(2)
            }
        }
        .padding(compact ? 10 : 0)
        .background {
            if compact {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.13), lineWidth: 1)
                    )
            }
        }
        .onAppear {
            store.refreshIfNeeded()
        }
    }

    private var header: some View {
        HStack {
            Label("Audio", systemImage: "speaker.wave.2")
                .font(compact ? .caption.weight(.semibold) : .headline)
                .foregroundStyle(primaryColor)

            Spacer()

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .frame(width: compact ? 24 : 28, height: compact ? 22 : 26)
            }
            .buttonStyle(.plain)
            .disabled(store.isRefreshing)
            .foregroundStyle(primaryColor.opacity(store.isRefreshing ? 0.35 : 0.85))
            .background(controlButtonBackground, in: RoundedRectangle(cornerRadius: 7))
            .help("Refresh Audio")
        }
    }

    @ViewBuilder
    private var defaultOutputCard: some View {
        if let defaultDevice {
            VStack(alignment: .leading, spacing: compact ? 7 : 10) {
                HStack(spacing: 8) {
                    Image(systemName: defaultDevice.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .foregroundStyle(.green)
                        .frame(width: compact ? 18 : 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("System Volume")
                            .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                            .foregroundStyle(primaryColor)

                        Text(defaultDevice.name)
                            .font(.caption2)
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        store.setDeviceMuted(!defaultDevice.isMuted, deviceID: defaultDevice.id)
                    } label: {
                        Image(systemName: defaultDevice.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                    }
                    .buttonStyle(.plain)
                    .disabled(!defaultDevice.supportsMute)
                    .foregroundStyle(defaultDevice.supportsMute ? .green : secondaryColor)
                    .background(controlButtonBackground, in: RoundedRectangle(cornerRadius: 7))
                    .help(defaultDevice.isMuted ? "Unmute" : "Mute")
                }

                AudioSlider(
                    value: defaultDevice.volume,
                    isEnabled: defaultDevice.supportsVolume,
                    tint: .green,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                    onChange: { store.setDeviceVolume($0, deviceID: defaultDevice.id) }
                )
            }
            .padding(compact ? 8 : 14)
            .background(panelBackground)
        } else {
            Text(store.isRefreshing ? "Scanning Audio" : "No output devices found.")
                .font(compact ? .caption : .callout)
                .foregroundStyle(secondaryColor)
                .frame(maxWidth: .infinity, minHeight: compact ? 64 : 110, alignment: .center)
                .background(panelBackground)
        }
    }

    private var outputDevicesSection: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            sectionTitle("Output Devices", systemImage: "hifispeaker.2")

            LazyVGrid(columns: deviceColumns, spacing: compact ? 7 : 10) {
                ForEach(store.outputDevices) { device in
                    outputDeviceCard(device)
                }
            }
        }
    }

    private func outputDeviceCard(_ device: AudioOutputDevice) -> some View {
        Button {
            if !device.isDefault {
                store.setDefaultOutputDevice(device.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: device.isDefault ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: compact ? 10 : 12, weight: .semibold))
                        .foregroundStyle(device.isDefault ? .green : secondaryColor)

                    Text(device.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                }

                HStack {
                    Text(device.transportName)
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)

                    Spacer()

                    Text(device.supportsVolume ? "\(Int(device.volume.rounded()))%" : "--")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(device.supportsVolume ? .green : secondaryColor)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if device.isDefault {
                    selectedPanelBackground
                } else {
                    panelBackground
                }
            }
        }
        .buttonStyle(.plain)
        .help(device.isDefault ? "Default Output" : "Set as Output")
    }

    private var appVolumeSection: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            sectionTitle("App Volume", systemImage: "app.badge")

            switch store.captureSupport {
            case .available:
                Text("Per-app processing needs Screen & System Audio Recording permission; current values are saved as app profiles.")
                    .font(.caption2)
                    .foregroundStyle(secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    openAudioPrivacySettings()
                } label: {
                    Label("Open System Settings", systemImage: "gearshape")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(primaryColor.opacity(0.85))
                .padding(.vertical, 5)
                .background(controlButtonBackground, in: RoundedRectangle(cornerRadius: 7))
            case .unsupported(let reason):
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.appItems.isEmpty {
                Text("No running apps found.")
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
                    .frame(maxWidth: .infinity, minHeight: compact ? 52 : 86, alignment: .center)
                    .background(panelBackground)
            } else {
                VStack(spacing: compact ? 6 : 8) {
                    ForEach(store.appItems.prefix(compact ? 5 : 12)) { item in
                        appVolumeRow(item)
                    }
                }
            }
        }
    }

    private func appVolumeRow(_ item: AudioAppVolumeItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                appIcon(item.icon)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(item.isIgnored ? secondaryColor : primaryColor)
                        .lineLimit(1)

                    Text(item.isRunning ? "Running" : "Pinned")
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                }

                Spacer()

                appActionButton(
                    systemImage: item.isMuted ? "speaker.slash.fill" : "speaker.wave.2",
                    isActive: item.isMuted,
                    help: item.isMuted ? "Unmute App" : "Mute App"
                ) {
                    store.setAppMuted(!item.isMuted, itemID: item.id)
                }

                Menu {
                    ForEach(AudioBoostLevel.allCases) { level in
                        Button(level.title) {
                            store.setAppBoost(level, itemID: item.id)
                        }
                    }
                } label: {
                    Text(item.boost.title)
                        .font(.caption2.weight(.semibold))
                        .frame(width: 28, height: 22)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Boost")

                appActionButton(
                    systemImage: item.isPinned ? "pin.fill" : "pin",
                    isActive: item.isPinned,
                    help: item.isPinned ? "Unpin App" : "Pin App"
                ) {
                    store.togglePinned(itemID: item.id)
                }

                appActionButton(
                    systemImage: item.isIgnored ? "eye.slash.fill" : "eye",
                    isActive: item.isIgnored,
                    help: item.isIgnored ? "Include App" : "Ignore App"
                ) {
                    store.toggleIgnored(itemID: item.id)
                }
            }

            AudioSlider(
                value: item.volume,
                isEnabled: !item.isIgnored,
                tint: .cyan,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                onChange: { store.setAppVolume($0, itemID: item.id) }
            )
        }
        .padding(8)
        .background {
            if item.isIgnored {
                mutedPanelBackground
            } else {
                panelBackground
            }
        }
    }

    private func openAudioPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func sectionTitle(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(secondaryColor)
    }

    @ViewBuilder
    private func appIcon(_ icon: NSImage?) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 18 : 22, height: compact ? 18 : 22)
                .cornerRadius(4)
        } else {
            Image(systemName: "app")
                .frame(width: compact ? 18 : 22, height: compact ? 18 : 22)
                .foregroundStyle(secondaryColor)
        }
    }

    private func appActionButton(
        systemImage: String,
        isActive: Bool,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .cyan : primaryColor.opacity(0.72))
        .background(controlButtonBackground, in: RoundedRectangle(cornerRadius: 7))
        .help(help)
    }

    private var deviceColumns: [GridItem] {
        if store.outputDevices.count <= 1 {
            return [GridItem(.flexible(), spacing: compact ? 7 : 10)]
        }

        return [
            GridItem(.flexible(), spacing: compact ? 7 : 10),
            GridItem(.flexible(), spacing: compact ? 7 : 10)
        ]
    }

    private var primaryColor: Color {
        compact ? .white : .primary
    }

    private var secondaryColor: Color {
        compact ? .white.opacity(0.55) : .secondary
    }

    private var controlButtonBackground: Color {
        compact ? Color.white.opacity(0.08) : Color.primary.opacity(0.06)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(compact ? Color.white.opacity(0.07) : Color.primary.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(compact ? Color.white.opacity(0.12) : Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    private var selectedPanelBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(compact ? Color.green.opacity(0.18) : Color.green.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.32), lineWidth: 1)
            )
    }

    private var mutedPanelBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(compact ? Color.white.opacity(0.04) : Color.primary.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(compact ? Color.white.opacity(0.08) : Color.primary.opacity(0.04), lineWidth: 1)
            )
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
        HStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: 0...100
            )
            .tint(isEnabled ? tint : secondaryColor)
            .disabled(!isEnabled)

            Text(isEnabled ? "\(Int(value.rounded()))%" : "--")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isEnabled ? tint : secondaryColor)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
