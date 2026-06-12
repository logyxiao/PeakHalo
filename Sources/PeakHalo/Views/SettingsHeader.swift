import SwiftUI

@ViewBuilder
func settingsHeader(title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(title)
            .font(.headline)
        Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
