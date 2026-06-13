import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject private var preferences = DisplayPreferencesStore.shared
    @ObservedObject private var displayService = DisplayService.shared
    @ObservedObject private var languageStore = AppLanguageStore.shared

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $languageStore.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.localizedName)
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Language")
            } footer: {
                Text("Choose the language used by PeakHalo.")
            }

            Section {
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
            } header: {
                Text("Display Placement")
            } footer: {
                Text("Choose where PeakHalo appears.")
            }

            Section {
                Picker("Main screen style", selection: $preferences.appearanceStyle) {
                    ForEach(NotchAppearanceStyle.allCases) { style in
                        Text(style.localizedName)
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Display Style")
            } footer: {
                Text(preferences.appearanceStyle.localizedDescription)
            }

            Section {
                Toggle(
                    "Hide PeakHalo during screenshots and recordings",
                    isOn: $preferences.hideFromScreenCapture
                )
            } header: {
                Text("Screen Capture")
            } footer: {
                Text("Control whether PeakHalo is visible in screenshots and recordings.")
            }

            Section {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(ResourceMonitorKind.allCases) { resource in
                        collapsedMonitorToggle(resource)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Collapsed Monitors")
            } footer: {
                Text("Choose which monitors appear while the notch or island is collapsed.")
            }

            Section {
                Picker("Open control panel with", selection: $preferences.panelActivationMode) {
                    ForEach(PanelActivationMode.allCases) { mode in
                        Text(mode.localizedName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Panel Opening")
            } footer: {
                Text(preferences.panelActivationMode.localizedDescription)
            }
        }
        .formStyle(.grouped)
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
