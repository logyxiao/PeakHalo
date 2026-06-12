import SwiftUI

struct BatteryDevicesView: View {
    let compact: Bool
    @ObservedObject private var store = BatteryDeviceStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                deviceList

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
    private var deviceList: some View {
        if store.devices.isEmpty {
            Text(store.isRefreshing ? "Scanning Batteries" : "No battery devices found.")
                .font(compact ? .caption : .callout)
                .foregroundStyle(secondaryColor)
                .frame(maxWidth: .infinity, minHeight: compact ? 64 : 110, alignment: .center)
        } else {
            VStack(spacing: compact ? 3 : 5) {
                ForEach(store.devices.prefix(compact ? 8 : 16)) { device in
                    batteryRow(device)
                }
            }
        }
    }

    private func batteryRow(_ device: BatteryDevice) -> some View {
        HStack(spacing: compact ? 9 : 12) {
            HStack(spacing: compact ? 8 : 10) {
                Circle()
                    .fill(iconFill(for: device))
                    .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                    .overlay {
                        Image(systemName: iconName(for: device.kind))
                            .font(.system(size: compact ? 15 : 17, weight: .semibold))
                            .foregroundStyle(iconForeground(for: device))
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)

                    Text(subtitle(for: device))
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }
                .frame(width: compact ? 176 : 230, alignment: .leading)
            }

            Image(systemName: device.isCharging == true ? "bolt.fill" : "battery.100percent")
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
                .foregroundStyle(device.isCharging == true ? .yellow : batteryTint(for: device.clampedLevel))

            BatteryLevelBar(
                value: device.clampedLevel,
                tint: batteryTint(for: device.clampedLevel),
                primaryColor: primaryColor,
                secondaryColor: secondaryColor
            )
            .layoutPriority(1)

            Text(levelText(for: device.clampedLevel))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(device.clampedLevel == nil ? secondaryColor : primaryColor.opacity(0.72))
                .frame(width: 42, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 39 : 44, maxHeight: compact ? 39 : 44)
        .contentShape(Rectangle())
        .help(Text(device.name))
        .contextMenu {
            Button("Refresh Batteries") {
                store.refresh()
            }
        }
    }

    private func subtitle(for device: BatteryDevice) -> String {
        var parts = [device.kind.title]

        if let detail = device.detail, !detail.isEmpty, detail != device.kind.title {
            parts.append(detail)
        } else if device.clampedLevel == nil {
            parts.append(String(localized: "Battery unavailable"))
        }

        return parts.joined(separator: " - ")
    }

    private func levelText(for level: Double?) -> String {
        guard let level else { return "--" }
        return "\(Int(level.rounded()))%"
    }

    private func iconName(for kind: BatteryDeviceKind) -> String {
        switch kind {
        case .computer:
            "laptopcomputer"
        case .headphones:
            "headphones"
        case .trackpad:
            "rectangle.and.hand.point.up.left.fill"
        case .keyboard:
            "keyboard"
        case .mouse:
            "computermouse"
        case .unknown:
            "battery.50percent"
        }
    }

    private func iconFill(for device: BatteryDevice) -> Color {
        let base = kindTint(for: device.kind)
        return compact ? base.opacity(0.95) : base.opacity(colorScheme == .dark ? 0.22 : 0.14)
    }

    private func iconForeground(for device: BatteryDevice) -> Color {
        compact ? .white : kindTint(for: device.kind)
    }

    private func kindTint(for kind: BatteryDeviceKind) -> Color {
        switch kind {
        case .computer:
            Color(red: 0.20, green: 0.64, blue: 1.0)
        case .headphones:
            Color(red: 0.31, green: 0.74, blue: 1.0)
        case .trackpad:
            Color(red: 0.72, green: 0.42, blue: 1.0)
        case .keyboard:
            Color(red: 0.30, green: 0.78, blue: 0.62)
        case .mouse:
            Color(red: 1.0, green: 0.64, blue: 0.24)
        case .unknown:
            secondaryColor
        }
    }

    private func batteryTint(for level: Double?) -> Color {
        guard level != nil else { return secondaryColor.opacity(0.72) }
        return controlProgressColor
    }

    private var primaryColor: Color {
        compact ? .white : .primary
    }

    private var secondaryColor: Color {
        compact ? .white.opacity(0.56) : .secondary
    }

    private var controlProgressColor: Color {
        colorScheme == .dark
            ? Color(red: 0.36, green: 0.88, blue: 0.52)
            : Color(red: 0.05, green: 0.62, blue: 0.28)
    }
}

private struct BatteryLevelBar: View {
    let value: Double?
    let tint: Color
    let primaryColor: Color
    let secondaryColor: Color

    private var progress: CGFloat {
        CGFloat(min(1, max(0, (value ?? 0) / 100)))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(secondaryColor.opacity(0.22))
                    .frame(height: 5)

                Capsule()
                    .fill(tint.opacity(value == nil ? 0.28 : 1))
                    .frame(width: max(width * progress, value == nil ? 0 : 4), height: 5)
                    .shadow(color: tint.opacity(value == nil ? 0 : 0.18), radius: 3, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 16)
        .accessibilityValue(value.map { "\(Int($0.rounded()))%" } ?? "--")
    }
}
