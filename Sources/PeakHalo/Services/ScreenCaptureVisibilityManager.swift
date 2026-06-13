import AppKit
import Combine

enum ScreenCaptureProcessDetector {
    private static let systemCaptureBundleIdentifiers: Set<String> = [
        "com.apple.screenshot",
        "com.apple.screencapture",
        "com.apple.screencaptureui",
        "com.apple.screencapturekit.screencaptureagent"
    ]

    private static let systemCaptureExecutableNames: Set<String> = [
        "screencapture",
        "screenshot",
        "screencaptureui",
        "screencaptureagent",
        "screencapturekitagent"
    ]

    static func isSystemCaptureProcess(
        processName: String?,
        bundleIdentifier: String?,
        executablePath: String?
    ) -> Bool {
        if let bundleIdentifier,
           systemCaptureBundleIdentifiers.contains(bundleIdentifier.lowercased()) {
            return true
        }

        guard let executableName = resolvedExecutableName(
            processName: processName,
            executablePath: executablePath
        ) else {
            return false
        }

        guard systemCaptureExecutableNames.contains(executableName) else {
            return false
        }

        guard let executablePath else {
            return true
        }

        return executablePath == "/usr/sbin/screencapture"
            || executablePath.hasPrefix("/System/")
    }

    private static func resolvedExecutableName(
        processName: String?,
        executablePath: String?
    ) -> String? {
        if let executablePath,
           let name = executablePath.split(separator: "/").last {
            return String(name).lowercased()
        }

        return processName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum ScreenCaptureWindowSharingPolicy: Equatable {
    case included
    case excluded

    var nsWindowSharingType: NSWindow.SharingType {
        switch self {
        case .included:
            .readOnly
        case .excluded:
            .none
        }
    }
}

struct ScreenCaptureWindowPresentationPolicy: Equatable {
    let sharingPolicy: ScreenCaptureWindowSharingPolicy
    let shouldOrderOut: Bool
    let shouldEnsureVisible: Bool

    static func resolved(
        hideFromScreenCapture: Bool,
        isSystemCaptureActive: Bool
    ) -> ScreenCaptureWindowPresentationPolicy {
        guard hideFromScreenCapture else {
            return ScreenCaptureWindowPresentationPolicy(
                sharingPolicy: .included,
                shouldOrderOut: false,
                shouldEnsureVisible: true
            )
        }

        return ScreenCaptureWindowPresentationPolicy(
            sharingPolicy: .excluded,
            shouldOrderOut: isSystemCaptureActive,
            shouldEnsureVisible: false
        )
    }
}

@MainActor
final class ScreenCaptureVisibilityManager {
    static let shared = ScreenCaptureVisibilityManager()

    private let windows = NSHashTable<NSWindow>.weakObjects()
    private var hiddenWindowIdentifiers = Set<ObjectIdentifier>()
    private var isSystemCaptureActive = false
    private var capturePollingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        DisplayPreferencesStore.shared.$hideFromScreenCapture
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    self.startCaptureActivityPolling()
                } else {
                    self.stopCaptureActivityPolling()
                    self.isSystemCaptureActive = false
                }
                self.updateAllWindows()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didLaunchApplicationNotification
        )
        .sink { [weak self] _ in
            self?.scheduleCaptureActivityRefresh()
        }
        .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.didTerminateApplicationNotification
        )
        .sink { [weak self] _ in
            self?.scheduleCaptureActivityRefresh()
        }
        .store(in: &cancellables)

        if DisplayPreferencesStore.shared.hideFromScreenCapture {
            startCaptureActivityPolling()
        }
    }

    func register(_ window: NSWindow) {
        windows.add(window)
        applyVisibility(to: window)
    }

    func unregister(_ window: NSWindow) {
        windows.remove(window)
        hiddenWindowIdentifiers.remove(ObjectIdentifier(window))
    }

    func updateAllWindows() {
        refreshCaptureActivity()
        for window in windows.allObjects {
            applyVisibility(to: window)
        }
    }

    private func applyVisibility(to window: NSWindow) {
        let presentation = ScreenCaptureWindowPresentationPolicy.resolved(
            hideFromScreenCapture: DisplayPreferencesStore.shared.hideFromScreenCapture,
            isSystemCaptureActive: isSystemCaptureActive
        )
        window.sharingType = presentation.sharingPolicy.nsWindowSharingType

        if presentation.shouldOrderOut {
            hideWindowForActiveCapture(window)
        } else {
            restoreWindowIfNeeded(window, forceVisible: presentation.shouldEnsureVisible)
        }
    }

    private func hideWindowForActiveCapture(_ window: NSWindow) {
        let identifier = ObjectIdentifier(window)
        guard window.isVisible else { return }

        hiddenWindowIdentifiers.insert(identifier)
        window.orderOut(nil)
    }

    private func restoreWindowIfNeeded(_ window: NSWindow, forceVisible: Bool = false) {
        let identifier = ObjectIdentifier(window)
        let wasHiddenForCapture = hiddenWindowIdentifiers.remove(identifier) != nil
        guard wasHiddenForCapture || (forceVisible && !window.isVisible) else { return }

        window.orderFrontRegardless()
    }

    private func startCaptureActivityPolling() {
        guard capturePollingTask == nil else { return }

        capturePollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateCaptureActivityState()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    private func stopCaptureActivityPolling() {
        capturePollingTask?.cancel()
        capturePollingTask = nil
    }

    private func scheduleCaptureActivityRefresh() {
        guard DisplayPreferencesStore.shared.hideFromScreenCapture else { return }

        Task { @MainActor [weak self] in
            self?.updateCaptureActivityState()
            try? await Task.sleep(for: .milliseconds(100))
            self?.updateCaptureActivityState()
        }
    }

    private func updateCaptureActivityState() {
        let wasActive = isSystemCaptureActive
        refreshCaptureActivity()

        if wasActive != isSystemCaptureActive {
            for window in windows.allObjects {
                applyVisibility(to: window)
            }
        }
    }

    private func refreshCaptureActivity() {
        isSystemCaptureActive = NSWorkspace.shared.runningApplications.contains { application in
            ScreenCaptureProcessDetector.isSystemCaptureProcess(
                processName: application.localizedName,
                bundleIdentifier: application.bundleIdentifier,
                executablePath: application.executableURL?.path
            )
        }
    }
}
