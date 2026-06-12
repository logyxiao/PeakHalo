import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject private var preferences = DisplayPreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        }
    }
}
