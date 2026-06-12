import AppKit
import Combine

@MainActor
final class ScreenCaptureVisibilityManager {
    static let shared = ScreenCaptureVisibilityManager()

    private let windows = NSHashTable<NSWindow>.weakObjects()
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = DisplayPreferencesStore.shared.$hideFromScreenCapture
            .sink { [weak self] _ in
                self?.updateAllWindows()
            }
    }

    func register(_ window: NSWindow) {
        windows.add(window)
        applyVisibility(to: window)
    }

    func unregister(_ window: NSWindow) {
        windows.remove(window)
    }

    func updateAllWindows() {
        for window in windows.allObjects {
            applyVisibility(to: window)
        }
    }

    private func applyVisibility(to window: NSWindow) {
        window.sharingType = DisplayPreferencesStore.shared.hideFromScreenCapture ? .none : .readOnly
    }
}
