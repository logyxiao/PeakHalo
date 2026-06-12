import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject private var preferences = DisplayPreferencesStore.shared
    @ObservedObject private var displayService = DisplayService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader(
                title: "Display Placement",
                subtitle: "Choose where the notch monitor appears."
            )

            Toggle("Show on all displays", isOn: $preferences.showOnAllDisplays)

            Picker("Show on a specific display", selection: $preferences.selectedDisplayID) {
                ForEach(displayService.displays) { display in
                    Text(display.displayName)
                        .tag(Optional(display.id))
                }
            }
            .disabled(preferences.showOnAllDisplays || displayService.displays.isEmpty)
            .onAppear {
                ensureValidDisplaySelection()
            }
            .onChange(of: displayService.displays) { _, _ in
                ensureValidDisplaySelection()
            }

            Divider()

            settingsHeader(
                title: "Display Style",
                subtitle: "Switch between the edge-attached notch and the floating island."
            )

            Picker("Main screen style", selection: $preferences.appearanceStyle) {
                ForEach(NotchAppearanceStyle.allCases) { style in
                    Text(style.localizedName)
                        .tag(style)
                }
            }
            .pickerStyle(.segmented)

            Text(preferences.appearanceStyle.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            settingsHeader(
                title: "Panel Opening",
                subtitle: "Choose how the control panel is expanded."
            )

            Picker("Open control panel with", selection: $preferences.panelActivationMode) {
                ForEach(PanelActivationMode.allCases) { mode in
                    Text(mode.localizedName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(preferences.panelActivationMode.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ensureValidDisplaySelection() {
        preferences.selectedDisplayID = displayService.fallbackDisplayID(
            for: preferences.selectedDisplayID
        )
    }
}
