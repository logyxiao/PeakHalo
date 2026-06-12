import CoreGraphics
import SwiftUI

struct DisplayControlsView: View {
    let compact: Bool
    @ObservedObject private var controller = DisplayControlController.shared

    private var visibleDisplays: [ControlledDisplay] {
        controller.displays
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            header

            if visibleDisplays.isEmpty {
                Text(controller.isRefreshing ? "Scanning Displays" : "No Controllable Displays")
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(secondaryColor)
                    .frame(maxWidth: .infinity, minHeight: compact ? 70 : 120, alignment: .center)
                    .background(panelBackground)
            } else {
                ScrollView {
                    LazyVGrid(columns: displayGridColumns, spacing: compact ? 8 : 12) {
                        ForEach(visibleDisplays) { display in
                            displayCard(display)
                        }
                    }
                }
                .frame(maxHeight: compact ? 220 : nil)
            }

            if let message = controller.lastMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Built-in displays use the system brightness interface. External displays try DDC/CI brightness control.")
                .font(.caption2)
                .foregroundStyle(secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
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
            controller.refreshIfNeeded()
        }
    }

    private var header: some View {
        HStack {
            Label("Display Controls", systemImage: "display.2")
                .font(compact ? .caption.weight(.semibold) : .headline)
                .foregroundStyle(primaryColor)

            Spacer()

            Button {
                controller.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: compact ? 11 : 13, weight: .semibold))
                    .frame(width: compact ? 24 : 28, height: compact ? 22 : 26)
            }
            .buttonStyle(.plain)
            .disabled(controller.isRefreshing)
            .foregroundStyle(primaryColor.opacity(controller.isRefreshing ? 0.35 : 0.85))
            .background(controlButtonBackground, in: RoundedRectangle(cornerRadius: 7))
            .help("Refresh Displays")
        }
    }

    private var displayGridColumns: [GridItem] {
        if visibleDisplays.count <= 1 {
            return [GridItem(.flexible(), spacing: compact ? 8 : 12)]
        }

        return [
            GridItem(.flexible(), spacing: compact ? 8 : 12),
            GridItem(.flexible(), spacing: compact ? 8 : 12)
        ]
    }

    private func displayCard(_ display: ControlledDisplay) -> some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack(spacing: 8) {
                Image(systemName: display.isBuiltIn ? "macbook" : "display")
                    .font(.system(size: compact ? 11 : 15, weight: .semibold))
                    .foregroundStyle(display.isBuiltIn ? .orange : .indigo)
                    .frame(width: compact ? 18 : 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .font(compact ? .caption.weight(.medium) : .callout.weight(.medium))
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)

                    Text(display.isBuiltIn ? "Built-in" : "External")
                        .font(.caption2)
                        .foregroundStyle(secondaryColor)
                }

                Spacer()
            }

            DisplayControlSlider(
                title: "Brightness",
                systemImage: "sun.max",
                value: controller.value(for: display.id, control: .brightness),
                isEnabled: display.supportsBrightness,
                unavailableText: display.unavailableReason(for: .brightness),
                compact: compact,
                primaryColor: primaryColor,
                secondaryColor: secondaryColor,
                tint: .orange,
                onChange: { controller.setValue($0, control: .brightness, displayID: display.id) }
            )
        }
        .padding(compact ? 8 : 14)
        .background(panelBackground)
    }

    private var primaryColor: Color {
        compact ? .white : .primary
    }

    private var secondaryColor: Color {
        compact ? .white.opacity(0.52) : .secondary
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
}

private struct DisplayControlSlider: View {
    let title: LocalizedStringKey
    let systemImage: String
    let value: Double
    let isEnabled: Bool
    let unavailableText: String?
    let compact: Bool
    let primaryColor: Color
    let secondaryColor: Color
    let tint: Color
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(isEnabled ? tint : secondaryColor)
                    .frame(width: compact ? 72 : 92, alignment: .leading)

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
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isEnabled ? tint : secondaryColor)
                    .frame(width: compact ? 36 : 46, alignment: .trailing)
            }

            if !isEnabled, let unavailableText {
                Text(unavailableText)
                    .font(.caption2)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(compact ? 1 : 2)
                    .padding(.leading, compact ? 80 : 100)
            }
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
