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

            collapsedMonitorSection

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

    private var collapsedMonitorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsHeader(
                title: "Collapsed Monitors",
                subtitle: "Choose which monitors appear while the notch or island is collapsed."
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(ResourceMonitorKind.allCases) { resource in
                    collapsedMonitorToggle(resource)
                }
            }
        }
    }

    private func collapsedMonitorToggle(_ resource: ResourceMonitorKind) -> some View {
        Toggle(
            isOn: Binding(
                get: { preferences.collapsedVisibleMonitors.contains(resource) },
                set: { preferences.setCollapsedMonitor(resource, isVisible: $0) }
            )
        ) {
            Label {
                Text(resource.title)
            } icon: {
                Image(systemName: resource.symbol)
                    .foregroundStyle(resource.tint)
            }
        }
        .toggleStyle(.checkbox)
    }

    private func ensureValidDisplaySelection() {
        preferences.selectedDisplayID = displayService.fallbackDisplayID(
            for: preferences.selectedDisplayID
        )
    }
}
