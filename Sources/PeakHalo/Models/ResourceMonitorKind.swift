import SwiftUI

enum ResourceMonitorKind: String, CaseIterable, Identifiable, Hashable {
    case cpu
    case gpu
    case memory
    case network
    case storage
    case battery

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .cpu:
            "CPU"
        case .gpu:
            "GPU"
        case .memory:
            "Memory"
        case .network:
            "Network"
        case .storage:
            "Storage"
        case .battery:
            "Battery"
        }
    }

    var symbol: String {
        switch self {
        case .cpu:
            "cpu"
        case .gpu:
            "display"
        case .memory:
            "memorychip"
        case .network:
            "arrow.up.arrow.down"
        case .storage:
            "internaldrive"
        case .battery:
            "battery.75percent"
        }
    }

    var tint: Color {
        switch self {
        case .cpu:
            .blue
        case .gpu:
            .purple
        case .memory:
            .green
        case .network:
            .cyan
        case .storage:
            .orange
        case .battery:
            .yellow
        }
    }

    var supportsAppList: Bool {
        switch self {
        case .cpu, .memory:
            true
        case .gpu, .network, .storage, .battery:
            false
        }
    }
}
