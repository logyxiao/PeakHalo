import AppKit
import CoreGraphics

@MainActor
final class DisplayService: NSObject, ObservableObject {
    static let shared = DisplayService()

    @Published private(set) var displays: [DisplayInfo] = []

    private override init() {
        super.init()

        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refresh() {
        let mainDisplayID = NSScreen.main?.peakHaloDisplayID
        displays = NSScreen.screens.compactMap { screen in
            guard let displayID = screen.peakHaloDisplayID else { return nil }

            return DisplayInfo(
                id: displayID,
                name: screen.localizedName,
                isMain: displayID == mainDisplayID,
                hasPhysicalNotch: screen.safeAreaInsets.top > 0
            )
        }
    }

    func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        if let displayID,
           let screen = NSScreen.screens.first(where: { $0.peakHaloDisplayID == displayID }) {
            return screen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    func visibleScreens(showOnAllDisplays: Bool, selectedDisplayID: CGDirectDisplayID?) -> [NSScreen] {
        if showOnAllDisplays {
            return NSScreen.screens
        }

        guard let screen = screen(for: selectedDisplayID) else {
            return []
        }

        return [screen]
    }

    func fallbackDisplayID(for selectedDisplayID: CGDirectDisplayID?) -> CGDirectDisplayID? {
        if let selectedDisplayID,
           NSScreen.screens.contains(where: { $0.peakHaloDisplayID == selectedDisplayID }) {
            return selectedDisplayID
        }

        return NSScreen.main?.peakHaloDisplayID ?? NSScreen.screens.first?.peakHaloDisplayID
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        refresh()
    }
}
