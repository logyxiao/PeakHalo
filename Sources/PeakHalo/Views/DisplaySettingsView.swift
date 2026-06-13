import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject private var preferences = DisplayPreferencesStore.shared
    @ObservedObject private var displayService = DisplayService.shared
    @ObservedObject private var languageStore = AppLanguageStore.shared
    @State private var selectedLanguage = AppLanguageStore.shared.language

    var body: some View {
        Form {
            Section {
                languageMenu
            } header: {
                Text(languageStore.localizedString("Language"))
            } footer: {
                Text(languageStore.localizedString("Choose the language used by PeakHalo."))
            }

            Section {
                Toggle(
                    languageStore.localizedString("Show on all displays"),
                    isOn: $preferences.showOnAllDisplays
                )

                Picker(
                    languageStore.localizedString("Show on a specific display"),
                    selection: $preferences.selectedDisplayID
                ) {
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
                Text(languageStore.localizedString("Display Placement"))
            } footer: {
                Text(languageStore.localizedString("Choose where PeakHalo appears."))
            }

            Section {
                Picker(languageStore.localizedString("Main screen style"), selection: $preferences.appearanceStyle) {
                    ForEach(NotchAppearanceStyle.allCases) { style in
                        Text(languageStore.localizedString(style.localizedNameKey))
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text(languageStore.localizedString("Display Style"))
            } footer: {
                Text(languageStore.localizedString(preferences.appearanceStyle.localizedDescriptionKey))
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
                Text(languageStore.localizedString("Collapsed Monitors"))
            } footer: {
                Text(languageStore.localizedString("Choose which monitors appear while the notch or island is collapsed."))
            }

            Section {
                Picker(
                    languageStore.localizedString("Open control panel with"),
                    selection: $preferences.panelActivationMode
                ) {
                    ForEach(PanelActivationMode.allCases) { mode in
                        Text(languageStore.localizedString(mode.localizedNameKey))
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text(languageStore.localizedString("Panel Opening"))
            } footer: {
                Text(languageStore.localizedString(preferences.panelActivationMode.localizedDescriptionKey))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedLanguage = languageStore.language
        }
        .onChange(of: languageStore.language) { _, language in
            selectedLanguage = language
        }
    }

    private var languageMenu: some View {
        HStack(spacing: 8) {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    selectLanguage(language)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedLanguage == language ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedLanguage == language ? Color.accentColor : .secondary)
                        Text(languageTitle(language))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(languageOptionBackground(isSelected: selectedLanguage == language))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func languageTitle(_ language: AppLanguage) -> String {
        AppLocalization.localizedString(language.localizationKey, language: selectedLanguage)
    }

    private func selectLanguage(_ language: AppLanguage) {
        selectedLanguage = language
        languageStore.setLanguage(language)
    }

    private func languageOptionBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }

    private func collapsedMonitorToggle(_ resource: ResourceMonitorKind) -> some View {
        Toggle(
            isOn: Binding(
                get: { preferences.collapsedVisibleMonitors.contains(resource) },
                set: { preferences.setCollapsedMonitor(resource, isVisible: $0) }
            )
        ) {
            Label {
                Text(languageStore.localizedString(resource.titleKey))
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
