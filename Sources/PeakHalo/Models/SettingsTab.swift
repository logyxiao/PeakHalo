import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case display
    case controls
    case permissions
    case about

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .display:
            "Display"
        case .controls:
            "Controls"
        case .permissions:
            "Permissions"
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
            "display screen monitor all specific appearance style notch dynamic island panel opening menu bar icon hover language locale english chinese system 语言 中文 英语 跟随系统"
        case .controls:
            "display controls brightness volume sound monitor"
        case .permissions:
            "permissions authorization privacy audio capture recording bluetooth system settings"
        case .about:
            "about version build app update github release download"
        }
    }

    var systemImage: String {
        switch self {
        case .display:
            "display"
        case .controls:
            "display.2"
        case .permissions:
            "lock.shield"
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
        case .permissions:
            .green
        case .about:
            .gray
        }
    }
}
