import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case display
    case controls
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
            "display screen monitor all specific appearance style notch dynamic island panel opening menu bar icon hover"
        case .controls:
            "display controls brightness volume sound monitor"
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
        case .privacy:
            .green
        case .metrics:
            .orange
        case .about:
            .gray
        }
    }
}
