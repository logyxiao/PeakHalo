import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case display
    case controls
    case appearance
    case privacy
    case metrics
    case about

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .display:
            "Display"
        case .controls:
            "Controls"
        case .appearance:
            "Appearance"
        case .privacy:
            "Privacy"
        case .metrics:
            "Metrics"
        case .about:
            "About"
        }
    }

    var title: LocalizedStringKey {
        LocalizedStringKey(localizationKey)
    }

    var searchText: String {
        switch self {
        case .display:
            "display screen monitor all specific"
        case .controls:
            "display controls brightness volume sound monitor"
        case .appearance:
            "appearance style notch dynamic island"
        case .privacy:
            "privacy screenshot recording capture hide"
        case .metrics:
            "metrics cpu gpu memory monitor network storage battery apps processes quit force"
        case .about:
            "about version app"
        }
    }

    var systemImage: String {
        switch self {
        case .display:
            "display"
        case .controls:
            "display.2"
        case .appearance:
            "paintpalette"
        case .privacy:
            "eye.slash"
        case .metrics:
            "chart.xyaxis.line"
        case .about:
            "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .display:
            .blue
        case .controls:
            .indigo
        case .appearance:
            .purple
        case .privacy:
            .green
        case .metrics:
            .orange
        case .about:
            .gray
        }
    }
}
