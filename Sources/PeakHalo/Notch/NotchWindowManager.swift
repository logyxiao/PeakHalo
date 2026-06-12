import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    private final class WindowContext {
        let displayID: CGDirectDisplayID
        let viewModel: NotchViewModel
        let panel: NotchPanel
        var screen: NSScreen
        var cancellables = Set<AnyCancellable>()

        init(displayID: CGDirectDisplayID, screen: NSScreen, viewModel: NotchViewModel, panel: NotchPanel) {
            self.displayID = displayID
            self.screen = screen
            self.viewModel = viewModel
            self.panel = panel
        }
    }

    private let preferences = DisplayPreferencesStore.shared
    private let displayService = DisplayService.shared
    private var contexts: [CGDirectDisplayID: WindowContext] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var isObserving = false

    private init() {}

    func show(metricsService: SystemMetricsService) {
        displayService.refresh()
        startObservingIfNeeded(metricsService: metricsService)
        syncWindows(metricsService: metricsService, animated: false)
    }

    func hide() {
        for context in contexts.values {
            ScreenCaptureVisibilityManager.shared.unregister(context.panel)
            context.panel.orderOut(nil)
            context.panel.close()
        }

        contexts.removeAll()
        cancellables.removeAll()
        isObserving = false
    }

    func open() {
        for context in contexts.values {
            context.viewModel.open()
        }
    }

    func close() {
        for context in contexts.values {
            context.viewModel.close()
        }
    }

    private func startObservingIfNeeded(metricsService: SystemMetricsService) {
        guard !isObserving else { return }
        isObserving = true

        Publishers.CombineLatest3(
            preferences.$showOnAllDisplays,
            preferences.$selectedDisplayID,
            preferences.$appearanceStyle
        )
        .sink { [weak self] _, _, _ in
            Task { @MainActor in
                self?.syncWindows(metricsService: metricsService, animated: true)
            }
        }
        .store(in: &cancellables)

        displayService.$displays
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.syncWindows(metricsService: metricsService, animated: false)
                }
            }
            .store(in: &cancellables)
    }

    private func syncWindows(metricsService: SystemMetricsService, animated: Bool) {
        if !preferences.showOnAllDisplays {
            let fallbackID = displayService.fallbackDisplayID(for: preferences.selectedDisplayID)
            if preferences.selectedDisplayID != fallbackID {
                preferences.selectedDisplayID = fallbackID
                return
            }
        }

        let screens = displayService.visibleScreens(
            showOnAllDisplays: preferences.showOnAllDisplays,
            selectedDisplayID: preferences.selectedDisplayID
        )
        let desiredIDs = Set(screens.compactMap(\.peakHaloDisplayID))

        for displayID in Set(contexts.keys).subtracting(desiredIDs) {
            removeContext(displayID: displayID)
        }

        for screen in screens {
            guard let displayID = screen.peakHaloDisplayID else { continue }

            if let context = contexts[displayID] {
                context.screen = screen
                updateFrame(for: context, animated: animated)
                context.panel.orderFrontRegardless()
            } else {
                createContext(
                    displayID: displayID,
                    screen: screen,
                    metricsService: metricsService,
                    animated: false
                )
            }
        }

        ScreenCaptureVisibilityManager.shared.updateAllWindows()
    }

    private func createContext(
        displayID: CGDirectDisplayID,
        screen: NSScreen,
        metricsService: SystemMetricsService,
        animated: Bool
    ) {
        let viewModel = NotchViewModel()
        let size = NotchGeometry.windowSize(
            for: screen,
            state: viewModel.state,
            style: preferences.appearanceStyle
        )
        let frame = NotchGeometry.windowFrame(size: size, on: screen, style: preferences.appearanceStyle)
        let panel = NotchPanel(contentRect: frame)
        let context = WindowContext(displayID: displayID, screen: screen, viewModel: viewModel, panel: panel)

        let hostingView = NotchHostingView(
            rootView: NotchRootView(
                viewModel: viewModel,
                metricsService: metricsService
            )
        )
        hostingView.onHoverChange = { [weak viewModel] isHovering in
            Task { @MainActor in
                viewModel?.setHovering(isHovering)
            }
        }
        panel.contentView = hostingView

        viewModel.$state
            .removeDuplicates()
            .sink { [weak self, weak context] state in
                Task { @MainActor in
                    guard let context else { return }
                    self?.updateFrame(for: context, animated: true, targetState: state)
                }
            }
            .store(in: &context.cancellables)

        contexts[displayID] = context
        ScreenCaptureVisibilityManager.shared.register(panel)
        updateFrame(for: context, animated: animated)
        panel.orderFrontRegardless()
    }

    private func removeContext(displayID: CGDirectDisplayID) {
        guard let context = contexts.removeValue(forKey: displayID) else { return }

        ScreenCaptureVisibilityManager.shared.unregister(context.panel)
        context.panel.orderOut(nil)
        context.panel.close()
    }

    private func updateFrame(
        for context: WindowContext,
        animated: Bool,
        targetState: NotchState? = nil
    ) {
        let state = targetState ?? context.viewModel.state
        let size = NotchGeometry.windowSize(
            for: context.screen,
            state: state,
            style: preferences.appearanceStyle
        )
        let frame = NotchGeometry.windowFrame(
            size: size,
            on: context.screen,
            style: preferences.appearanceStyle
        )

        if animated {
            let profile = frameAnimationProfile(for: state)
            NSAnimationContext.runAnimationGroup { animationContext in
                animationContext.duration = profile.duration
                animationContext.timingFunction = profile.timingFunction
                animationContext.allowsImplicitAnimation = true
                context.panel.animator().setFrame(frame, display: true)
            }
        } else {
            context.panel.setFrame(frame, display: true)
        }
    }

    private func frameAnimationProfile(
        for state: NotchState
    ) -> (duration: TimeInterval, timingFunction: CAMediaTimingFunction) {
        switch state {
        case .open:
            return (0.34, CAMediaTimingFunction(name: .easeOut))
        case .closed:
            return (0.28, CAMediaTimingFunction(name: .easeInEaseOut))
        }
    }
}
