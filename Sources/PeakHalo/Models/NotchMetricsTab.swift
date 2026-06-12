import SwiftUI

enum NotchMetricsTab: String, CaseIterable, Identifiable {
    case monitor
    case audio
    case controls

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .monitor:
            "Monitor"
        case .audio:
            "Audio"
        case .controls:
            "Controls"
        }
    }

    var symbol: String {
        switch self {
        case .monitor:
            "gauge.with.dots.needle.67percent"
        case .audio:
            "speaker.wave.2"
        case .controls:
            "display.2"
        }
    }
}
