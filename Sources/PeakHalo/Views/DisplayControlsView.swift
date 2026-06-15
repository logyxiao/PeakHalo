import CoreGraphics
import SwiftUI

struct DisplayControlsView: View {
    let compact: Bool
    @ObservedObject private var controller = DisplayControlController.shared
    @ObservedObject private var languageStore = AppLanguageStore.shared
    @Environment(\.colorScheme) private var colorScheme

    private var visibleDisplays: [ControlledDisplay] {
        controller.displays
    }

    var body: some View {
        if compact {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    displayList
                    appearanceControls
                        .padding(.top, 6)

                    if let message = controller.lastMessage {
                        Text(languageStore.localizedString(message))
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
                controller.refreshAppearanceState()
            }
        } else {
            Form {
                Section {
                    if visibleDisplays.isEmpty {
                        Text(languageStore.localizedString(controller.isRefreshing ? "Scanning Displays" : "No Controllable Displays"))
                            .font(.callout)
                            .foregroundStyle(secondaryColor)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                    } else {
                        ForEach(visibleDisplays) { display in
                            displayBrightnessRow(display)
                        }
                    }
                } header: {
                    Text(languageStore.localizedString("Connected Displays"))
                } footer: {
                    if let message = controller.lastMessage {
                        Text(languageStore.localizedString(message))
                            .foregroundStyle(.red)
                    } else {
                        Text(languageStore.localizedString("Adjust the brightness of your connected monitors."))
                    }
                }

                Section {
                    Toggle(languageStore.localizedString("Night Shift"), isOn: Binding(
                        get: { controller.appearanceState.isNightShiftEnabled },
                        set: { controller.setNightShiftEnabled($0) }
                    ))
                    .disabled(!controller.appearanceState.isNightShiftAvailable)

                    Toggle(languageStore.localizedString("True Tone"), isOn: Binding(
                        get: { controller.appearanceState.isTrueToneEnabled },
                        set: { controller.setTrueToneEnabled($0) }
                    ))
                    .disabled(!controller.appearanceState.isTrueToneAvailable)
                } header: {
                    Text(languageStore.localizedString("System Display"))
                } footer: {
                    Text(languageStore.localizedString("Night Shift and True Tone availability depends on Mac model and display support."))
                }
            }
            .formStyle(.grouped)
            .onAppear {
                controller.refreshIfNeeded()
                controller.refreshAppearanceState()
            }
        }
    }

    @ViewBuilder
    private var displayList: some View {
        if visibleDisplays.isEmpty {
            Text(languageStore.localizedString(controller.isRefreshing ? "Scanning Displays" : "No Controllable Displays"))
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

    private var appearanceControls: some View {
        VStack(spacing: 3) {
            appearanceToggleRow(
                title: "Night Shift",
                systemImage: "moon.stars.fill",
                isOn: controller.appearanceState.isNightShiftEnabled,
                isEnabled: controller.appearanceState.isNightShiftAvailable,
                onChange: controller.setNightShiftEnabled
            )
            appearanceToggleRow(
                title: "True Tone",
                systemImage: "circle.lefthalf.filled",
                isOn: controller.appearanceState.isTrueToneEnabled,
                isEnabled: controller.appearanceState.isTrueToneAvailable,
                onChange: controller.setTrueToneEnabled
            )
        }
    }

    private func appearanceToggleRow(
        title: String,
        systemImage: String,
        isOn: Bool,
        isEnabled: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: compact ? 8 : 10) {
                ZStack {
                    Circle()
                        .fill(appearanceAccentColor(isOn: isOn, isEnabled: isEnabled).opacity(isOn ? 0.95 : 0.14))

                    Image(systemName: systemImage)
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .foregroundStyle(isOn && isEnabled ? .white : appearanceAccentColor(isOn: isOn, isEnabled: isEnabled))
                }
                .frame(width: compact ? 30 : 34, height: compact ? 30 : 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(languageStore.localizedString(title))
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .foregroundStyle(isEnabled ? primaryColor : secondaryColor)
                        .lineLimit(1)

                    Text(languageStore.localizedString(isOn ? "On" : "Off"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isOn && isEnabled ? appearanceAccentColor(isOn: isOn, isEnabled: isEnabled) : secondaryColor)
                }

                Spacer(minLength: 8)

                Text(languageStore.localizedString(isOn ? "On" : "Off"))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isOn && isEnabled ? .white : secondaryColor)
                    .padding(.horizontal, compact ? 9 : 11)
                    .padding(.vertical, compact ? 4 : 5)
                    .background {
                        Capsule()
                            .fill(isOn && isEnabled ? appearanceAccentColor(isOn: isOn, isEnabled: isEnabled) : secondaryColor.opacity(0.14))
                    }
            }
            .padding(.horizontal, compact ? 7 : 9)
            .frame(maxWidth: .infinity, minHeight: compact ? 42 : 48, maxHeight: compact ? 42 : 48)
            .background {
                RoundedRectangle(cornerRadius: compact ? 10 : 12)
                    .fill(appearanceAccentColor(isOn: isOn, isEnabled: isEnabled).opacity(isOn && isEnabled ? 0.14 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 10 : 12)
                    .stroke(appearanceAccentColor(isOn: isOn, isEnabled: isEnabled).opacity(isOn && isEnabled ? 0.42 : 0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(Text(languageStore.localizedString(isEnabled ? title : "Unavailable")))
    }

    private func appearanceAccentColor(isOn: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else { return secondaryColor }
        return isOn ? controlProgressColor : secondaryColor
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

                    Text(languageStore.localizedString(display.isBuiltIn ? "Built-in" : "External"))
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
        .help(Text(display.supportsBrightness
            ? languageStore.localizedString("Brightness")
            : display.unavailableReason(for: .brightness) ?? languageStore.localizedString("Brightness")))
        .contextMenu {
            Button(languageStore.localizedString("Refresh Displays")) {
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
    @Published private(set) var lastMessage: LocalizedMessage?
    @Published private(set) var appearanceState = DisplayAppearanceState(
        isNightShiftAvailable: false,
        isNightShiftEnabled: false,
        isTrueToneAvailable: false,
        isTrueToneEnabled: false
    )

    private let service = DisplayControlService()
    private lazy var appearanceService = DisplayAppearanceService()
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
                self?.lastMessage = displays.isEmpty ? .string("No display control information is available.") : nil
            }
        }
    }

    func value(for displayID: CGDirectDisplayID, control: DisplayControlKind) -> Double {
        displays.first { $0.id == displayID }?.value(for: control) ?? control.defaultValue
    }

    func setNightShiftEnabled(_ isEnabled: Bool) {
        guard appearanceService.setNightShiftEnabled(isEnabled) else {
            lastMessage = .string("Night Shift is unavailable.")
            refreshAppearanceState()
            return
        }

        refreshAppearanceState()
        lastMessage = nil
    }

    func setTrueToneEnabled(_ isEnabled: Bool) {
        guard appearanceService.setTrueToneEnabled(isEnabled) else {
            lastMessage = .string("True Tone is unavailable.")
            refreshAppearanceState()
            return
        }

        refreshAppearanceState()
        lastMessage = nil
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

    func refreshAppearanceState() {
        appearanceState = appearanceService.state()
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
        lastMessage = LocalizedMessage(
            "%@ %@ is unavailable",
            arguments: [
                .string(displays[index].name),
                .message(result.control.localizedTitleMessage)
            ]
        )
    }
}
