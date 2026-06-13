import CoreGraphics
import SwiftUI

struct DisplayControlsView: View {
    let compact: Bool
    @ObservedObject private var controller = DisplayControlController.shared
    @Environment(\.colorScheme) private var colorScheme

    private var visibleDisplays: [ControlledDisplay] {
        controller.displays
    }

    var body: some View {
        if compact {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    displayList

                    if let message = controller.lastMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(secondaryColor)
                            .lineLimit(2)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: 246, alignment: .topLeading)
            .onAppear {
                controller.refreshIfNeeded()
            }
        } else {
            Form {
                Section {
                    if visibleDisplays.isEmpty {
                        Text(controller.isRefreshing ? "Scanning Displays" : "No Controllable Displays")
                            .font(.callout)
                            .foregroundStyle(secondaryColor)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                    } else {
                        ForEach(visibleDisplays) { display in
                            displayBrightnessRow(display)
                        }
                    }
                } header: {
                    Text("Connected Displays")
                } footer: {
                    if let message = controller.lastMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    } else {
                        Text("Adjust the brightness of your connected monitors.")
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear {
                controller.refreshIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var displayList: some View {
        if visibleDisplays.isEmpty {
            Text(controller.isRefreshing ? "Scanning Displays" : "No Controllable Displays")
                .font(.caption)
                .foregroundStyle(secondaryColor)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
        } else {
            VStack(spacing: 3) {
                ForEach(visibleDisplays.prefix(5)) { display in
                    displayBrightnessRow(display)
                }
            }
        }
    }

    private func displayBrightnessRow(_ display: ControlledDisplay) -> some View {
        HStack(spacing: compact ? 9 : 12) {
            HStack(spacing: compact ? 8 : 10) {
                Circle()
                    .fill(display.isBuiltIn ? Color.orange.opacity(0.95) : (compact ? Color.white.opacity(0.12) : Color.primary.opacity(0.08)))
                    .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)
                    .overlay {
                        Image(systemName: displayIconName(for: display))
                            .font(.system(size: compact ? 15 : 17, weight: .semibold))
                            .foregroundStyle(display.isBuiltIn ? .white : (compact ? secondaryColor : .primary.opacity(0.72)))
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)

                    Text(display.isBuiltIn ? "Built-in" : "External")
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }
                .frame(width: compact ? 176 : 230, alignment: .leading)
            }

            Image(systemName: "sun.max.fill")
                .font(.system(size: compact ? 13 : 15, weight: .semibold))
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
                .foregroundStyle(display.supportsBrightness ? controlProgressColor : primaryColor.opacity(0.24))

            DisplayBrightnessSlider(
                value: controller.value(for: display.id, control: .brightness),
                isEnabled: display.supportsBrightness,
                tint: controlProgressColor,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                onChange: { controller.setValue($0, control: .brightness, displayID: display.id) }
            )
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 39 : 44, maxHeight: compact ? 39 : 44)
        .contentShape(Rectangle())
        .help(display.supportsBrightness ? Text("Brightness") : Text(display.unavailableReason(for: .brightness) ?? "Brightness"))
        .contextMenu {
            Button("Refresh Displays") {
                controller.refresh()
            }
        }
    }

    private var primaryColor: Color {
        compact ? .white : .primary
    }

    private var secondaryColor: Color {
        compact ? .white.opacity(0.52) : .secondary
    }

    private var controlProgressColor: Color {
        colorScheme == .dark
            ? Color(red: 0.38, green: 0.80, blue: 1.0)
            : Color(red: 0.02, green: 0.48, blue: 0.88)
    }

    private func displayIconName(for display: ControlledDisplay) -> String {
        display.isBuiltIn ? "laptopcomputer" : "display"
    }
}

private struct DisplayBrightnessSlider: View {
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

@MainActor
final class DisplayControlController: ObservableObject {
    static let shared = DisplayControlController()

    @Published private(set) var displays: [ControlledDisplay] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastMessage: String?

    private let service = DisplayControlService()
    private let worker = DisplayControlWorker()
    private var hasLoaded = false

    private init() {}

    func refreshIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        worker.refresh(service: service) { [weak self] displays in
            Task { @MainActor in
                self?.hasLoaded = true
                self?.displays = displays
                self?.isRefreshing = false
                self?.lastMessage = displays.isEmpty ? String(localized: "No display control information is available.") : nil
            }
        }
    }

    func value(for displayID: CGDirectDisplayID, control: DisplayControlKind) -> Double {
        displays.first { $0.id == displayID }?.value(for: control) ?? control.defaultValue
    }

    func setValue(_ value: Double, control: DisplayControlKind, displayID: CGDirectDisplayID) {
        guard let index = displays.firstIndex(where: { $0.id == displayID }) else { return }
        let display = displays[index]
        guard display.supports(control) else { return }

        let clampedValue = DisplayControlService.clamp(value)
        displays[index].setValue(clampedValue, for: control)
        worker.setValue(
            clampedValue,
            control: control,
            display: display,
            service: service
        ) { [weak self] result in
            Task { @MainActor in
                self?.apply(result)
            }
        }
    }

    private func apply(_ result: DisplayWriteResult) {
        guard let index = displays.firstIndex(where: { $0.id == result.displayID }) else {
            return
        }

        displays[index].setValue(DisplayControlService.clamp(result.value), for: result.control)

        if result.success {
            lastMessage = nil
            return
        }

        displays[index].setSupported(false, for: result.control)
        lastMessage = "\(displays[index].name) \(result.control.title) \(String(localized: "is unavailable"))"
    }
}
