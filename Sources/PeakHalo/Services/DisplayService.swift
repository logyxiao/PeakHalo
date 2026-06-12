import AppKit
import CoreGraphics

@MainActor
final class DisplayService: ObservableObject {
    static let shared = DisplayService()

    @Published private(set) var displays: [DisplayInfo] = []

    private var observer: NSObjectProtocol?

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
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
}
