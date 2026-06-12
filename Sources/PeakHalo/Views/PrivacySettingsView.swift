import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject private var preferences = DisplayPreferencesStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader(
                title: "Privacy",
                subtitle: "Control whether the notch monitor is visible in screen captures."
            )

            Toggle(
                "Hide Dynamic Island during screenshots and recordings",
                isOn: $preferences.hideFromScreenCapture
            )
        }
    }
}
