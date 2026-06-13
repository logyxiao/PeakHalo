import SwiftUI

enum NotchMetricsTab: String, CaseIterable, Identifiable {
    case monitor
    case battery
    case audio
    case controls

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .monitor:
            "Monitor"
        case .battery:
            "Battery Devices"
        case .audio:
            "Audio"
        case .controls:
            "Controls"
        }
    }

    var title: LocalizedStringKey {
        LocalizedStringKey(titleKey)
    }

    var symbol: String {
        switch self {
        case .monitor:
            "gauge.with.dots.needle.67percent"
        case .battery:
            "battery.100percent"
        case .audio:
            "speaker.wave.2"
        case .controls:
            "display.2"
        }
    }
}
