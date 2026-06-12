import Foundation

enum BatteryDeviceKind: String, CaseIterable {
    case computer
    case headphones
    case trackpad
    case keyboard
    case mouse
    case unknown

    var title: String {
        switch self {
        case .computer:
            String(localized: "Computer")
        case .headphones:
            String(localized: "Headphones")
        case .trackpad:
            String(localized: "Trackpad")
        case .keyboard:
            String(localized: "Keyboard")
        case .mouse:
            String(localized: "Mouse")
        case .unknown:
            String(localized: "Unknown Device")
        }
    }

    var sortRank: Int {
        switch self {
        case .computer:
            0
        case .headphones:
            1
        case .trackpad:
            2
        case .keyboard:
            3
        case .mouse:
            4
        case .unknown:
            5
        }
    }
}

struct BatteryDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: BatteryDeviceKind
    let level: Double?
    let isCharging: Bool?
    let isConnected: Bool
    let detail: String?
    let source: String
    let updatedAt: Date

    var clampedLevel: Double? {
        level.map { min(100, max(0, $0)) }
    }

    var hasBatteryReading: Bool {
        clampedLevel != nil || isCharging != nil
    }
}
