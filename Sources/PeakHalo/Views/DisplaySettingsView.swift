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
        }
    }

    private func ensureValidDisplaySelection() {
        preferences.selectedDisplayID = displayService.fallbackDisplayID(
            for: preferences.selectedDisplayID
        )
    }
}
