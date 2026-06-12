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

enum PanelActivationMode: String, CaseIterable, Identifiable {
    case notchHover
    case menuBarIcon

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .notchHover:
            "Notch Hover"
        case .menuBarIcon:
            "Menu Bar Icon"
        }
    }

    var localizedDescription: LocalizedStringKey {
        switch self {
        case .notchHover:
            "Move the pointer into the notch or island to expand the controls."
        case .menuBarIcon:
            "Click the menu bar icon to expand or collapse the controls."
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

    @Published var panelActivationMode: PanelActivationMode {
        didSet {
            defaults.set(panelActivationMode.rawValue, forKey: Keys.panelActivationMode)
        }
    }

    @Published var hideFromScreenCapture: Bool {
        didSet {
            defaults.set(hideFromScreenCapture, forKey: Keys.hideFromScreenCapture)
        }
    }

    @Published var collapsedVisibleMonitors: Set<ResourceMonitorKind> {
        didSet {
            defaults.set(
                collapsedVisibleMonitors.map(\.rawValue).sorted(),
                forKey: Keys.collapsedVisibleMonitors
            )
        }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let showOnAllDisplays = "display.showOnAllDisplays"
        static let selectedDisplayID = "display.selectedDisplayID"
        static let appearanceStyle = "display.appearanceStyle"
        static let panelActivationMode = "display.panelActivationMode"
        static let hideFromScreenCapture = "privacy.hideFromScreenCapture"
        static let collapsedVisibleMonitors = "display.collapsedVisibleMonitors"
        static let legacyDynamicIslandVisibleMonitors = "display.dynamicIslandVisibleMonitors"
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

        if let rawMode = defaults.string(forKey: Keys.panelActivationMode),
           let storedMode = PanelActivationMode(rawValue: rawMode) {
            panelActivationMode = storedMode
        } else {
            panelActivationMode = .notchHover
        }

        hideFromScreenCapture = defaults.bool(forKey: Keys.hideFromScreenCapture)

        if let rawMonitors = defaults.stringArray(forKey: Keys.collapsedVisibleMonitors)
            ?? defaults.stringArray(forKey: Keys.legacyDynamicIslandVisibleMonitors) {
            let storedMonitors = Set(rawMonitors.compactMap(ResourceMonitorKind.init(rawValue:)))
            collapsedVisibleMonitors = storedMonitors
        } else {
            collapsedVisibleMonitors = [.cpu, .gpu, .memory, .network]
        }
    }

    func setCollapsedMonitor(_ resource: ResourceMonitorKind, isVisible: Bool) {
        if isVisible {
            collapsedVisibleMonitors.insert(resource)
        } else {
            collapsedVisibleMonitors.remove(resource)
        }
    }
}
