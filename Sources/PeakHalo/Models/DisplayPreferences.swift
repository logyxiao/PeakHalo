import CoreGraphics
import Foundation
import SwiftUI

enum NotchAppearanceStyle: String, CaseIterable, Identifiable {
    case standardNotch
    case dynamicIsland

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .standardNotch:
            "Standard Notch"
        case .dynamicIsland:
            "Dynamic Island"
        }
    }

    var localizedDescription: LocalizedStringKey {
        switch self {
        case .standardNotch:
            "Classic notch shape attached to the top edge of the screen."
        case .dynamicIsland:
            "Floating pill shape with a small gap from the top edge."
        }
    }
}

@MainActor
final class DisplayPreferencesStore: ObservableObject {
    static let shared = DisplayPreferencesStore()

    @Published var showOnAllDisplays: Bool {
        didSet {
            defaults.set(showOnAllDisplays, forKey: Keys.showOnAllDisplays)
        }
    }

    @Published var selectedDisplayID: CGDirectDisplayID? {
        didSet {
            if let selectedDisplayID {
                defaults.set(Int(selectedDisplayID), forKey: Keys.selectedDisplayID)
            } else {
                defaults.removeObject(forKey: Keys.selectedDisplayID)
            }
        }
    }

    @Published var appearanceStyle: NotchAppearanceStyle {
        didSet {
            defaults.set(appearanceStyle.rawValue, forKey: Keys.appearanceStyle)
        }
    }

    @Published var hideFromScreenCapture: Bool {
        didSet {
            defaults.set(hideFromScreenCapture, forKey: Keys.hideFromScreenCapture)
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let showOnAllDisplays = "display.showOnAllDisplays"
        static let selectedDisplayID = "display.selectedDisplayID"
        static let appearanceStyle = "display.appearanceStyle"
        static let hideFromScreenCapture = "privacy.hideFromScreenCapture"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showOnAllDisplays = defaults.bool(forKey: Keys.showOnAllDisplays)

        let storedDisplayID = defaults.integer(forKey: Keys.selectedDisplayID)
        selectedDisplayID = storedDisplayID > 0 ? CGDirectDisplayID(storedDisplayID) : nil

        if let rawStyle = defaults.string(forKey: Keys.appearanceStyle),
           let storedStyle = NotchAppearanceStyle(rawValue: rawStyle) {
            appearanceStyle = storedStyle
        } else {
            appearanceStyle = .standardNotch
        }

        hideFromScreenCapture = defaults.bool(forKey: Keys.hideFromScreenCapture)
    }
}
