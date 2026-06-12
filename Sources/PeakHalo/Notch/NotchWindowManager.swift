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
    private weak var metricsService: SystemMetricsService?
    private var isMenuBarPanelVisible = false
    private var isMenuBarPanelClosing = false
    private var menuBarAnchorRect: NSRect?
    private var menuBarDismissEventMonitor: Any?

    private init() {}

    func show(metricsService: SystemMetricsService) {
        self.metricsService = metricsService
        displayService.refresh()
        startObservingIfNeeded(metricsService: metricsService)
        syncWindows(metricsService: metricsService, animated: false)
    }

    func hide() {
        removeAllContexts()
        cancellables.removeAll()
        isObserving = false
        metricsService = nil
        isMenuBarPanelVisible = false
        isMenuBarPanelClosing = false
        menuBarAnchorRect = nil
        stopMenuBarDismissMonitoring()
    }

    func open() {
        if preferences.panelActivationMode == .menuBarIcon {
            showMenuBarPanel(anchorRect: nil)
            return
        }

        for context in contexts.values {
            context.viewModel.open()
        }
    }

    func open(fromMenuBarAnchor anchorRect: NSRect?) {
        if preferences.panelActivationMode == .menuBarIcon {
            showMenuBarPanel(anchorRect: anchorRect)
        } else {
            open()
        }
    }

    func close() {
        close(animated: true)
    }

    func close(animated: Bool) {
        if preferences.panelActivationMode == .menuBarIcon {
            hideMenuBarPanel(animated: animated)
            return
        }

        for context in contexts.values {
            context.viewModel.close()
        }
    }

    func toggle() {
        if preferences.panelActivationMode == .menuBarIcon {
            if isMenuBarPanelVisible {
                hideMenuBarPanel(animated: true)
            } else {
                showMenuBarPanel(anchorRect: nil)
            }
            return
        }

        if contexts.values.contains(where: { $0.viewModel.state == .open }) {
            close()
        } else {
            open()
        }
    }

    func toggle(fromMenuBarAnchor anchorRect: NSRect?) {
        if preferences.panelActivationMode == .menuBarIcon {
            if isMenuBarPanelVisible {
                if let anchorRect {
                    menuBarAnchorRect = anchorRect
                }
                hideMenuBarPanel(animated: true)
            } else {
                showMenuBarPanel(anchorRect: anchorRect)
            }
            return
        }

        toggle()
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

        preferences.$panelActivationMode
            .removeDuplicates()
            .sink { [weak self] mode in
                Task { @MainActor in
                    guard let self else { return }

                    switch mode {
                    case .menuBarIcon:
                        self.hideMenuBarPanel(animated: false)
                    case .notchHover:
                        self.isMenuBarPanelVisible = false
                        self.isMenuBarPanelClosing = false
                        self.menuBarAnchorRect = nil
                        self.stopMenuBarDismissMonitoring()
                        if let metricsService = self.metricsService {
                            self.syncWindows(metricsService: metricsService, animated: true)
                        }
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.dismissMenuBarPanelForExternalInteraction()
                }
            }
            .store(in: &cancellables)
    }

    private func syncWindows(metricsService: SystemMetricsService, animated: Bool) {
        if preferences.panelActivationMode == .menuBarIcon, !isMenuBarPanelVisible, !isMenuBarPanelClosing {
            removeAllContexts()
            ScreenCaptureVisibilityManager.shared.updateAllWindows()
            return
        }

        let screens: [NSScreen]
        if preferences.panelActivationMode == .menuBarIcon {
            guard let screen = menuBarPanelScreen() else {
                removeAllContexts()
                ScreenCaptureVisibilityManager.shared.updateAllWindows()
                return
            }
            screens = [screen]
        } else if !preferences.showOnAllDisplays {
            let fallbackID = displayService.fallbackDisplayID(for: preferences.selectedDisplayID)
            if preferences.selectedDisplayID != fallbackID {
                preferences.selectedDisplayID = fallbackID
                return
            }

            screens = displayService.visibleScreens(
                showOnAllDisplays: false,
                selectedDisplayID: preferences.selectedDisplayID
            )
        } else {
            screens = displayService.visibleScreens(
                showOnAllDisplays: true,
                selectedDisplayID: preferences.selectedDisplayID
            )
        }
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
        if preferences.panelActivationMode == .menuBarIcon, isMenuBarPanelVisible {
            viewModel.open()
        }

        let size = NotchGeometry.windowSize(
            for: screen,
            state: viewModel.state,
            style: preferences.appearanceStyle
        )
        let frame = panelFrame(size: size, on: screen)
        let panel = NotchPanel(contentRect: frame)
        let context = WindowContext(displayID: displayID, screen: screen, viewModel: viewModel, panel: panel)

        let hostingView = NotchHostingView(
            rootView: NotchRootView(
                viewModel: viewModel,
                metricsService: metricsService
            )
        )
        hostingView.onHoverChange = { [weak self, weak viewModel] isHovering in
            Task { @MainActor in
                guard self?.preferences.panelActivationMode == .notchHover else {
                    return
                }
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

    private func removeAllContexts() {
        for displayID in Array(contexts.keys) {
            removeContext(displayID: displayID)
        }
    }

    private func showMenuBarPanel(anchorRect: NSRect?) {
        guard let metricsService else { return }

        if let anchorRect {
            menuBarAnchorRect = anchorRect
        }
        isMenuBarPanelVisible = true
        isMenuBarPanelClosing = false
        startMenuBarDismissMonitoring()
        syncWindows(metricsService: metricsService, animated: false)

        for context in contexts.values {
            context.viewModel.open()
            context.panel.orderFrontRegardless()
        }
    }

    private func hideMenuBarPanel(animated: Bool) {
        guard isMenuBarPanelVisible || isMenuBarPanelClosing else {
            menuBarAnchorRect = nil
            stopMenuBarDismissMonitoring()
            removeAllContexts()
            return
        }

        isMenuBarPanelVisible = false
        isMenuBarPanelClosing = animated
        for context in contexts.values {
            context.viewModel.close()
        }

        guard let metricsService else {
            isMenuBarPanelClosing = false
            menuBarAnchorRect = nil
            stopMenuBarDismissMonitoring()
            removeAllContexts()
            return
        }

        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self, weak metricsService] in
                Task { @MainActor in
                    guard let self, let metricsService, !self.isMenuBarPanelVisible else { return }
                    self.isMenuBarPanelClosing = false
                    self.menuBarAnchorRect = nil
                    self.stopMenuBarDismissMonitoring()
                    self.syncWindows(metricsService: metricsService, animated: false)
                }
            }
        } else {
            isMenuBarPanelClosing = false
            menuBarAnchorRect = nil
            stopMenuBarDismissMonitoring()
            syncWindows(metricsService: metricsService, animated: false)
        }
    }

    private func menuBarPanelScreen() -> NSScreen? {
        guard let anchorRect = menuBarAnchorRect else {
            return displayService.screen(for: nil)
        }

        let anchorCenter = CGPoint(x: anchorRect.midX, y: anchorRect.midY)
        return NSScreen.screens.first { screen in
            screen.frame.contains(anchorCenter)
        } ?? displayService.screen(for: nil)
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
        let frame = panelFrame(size: size, on: context.screen)

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

    private func panelFrame(size: CGSize, on screen: NSScreen) -> NSRect {
        if preferences.panelActivationMode == .menuBarIcon,
           isMenuBarPanelVisible || isMenuBarPanelClosing {
            return NotchGeometry.menuBarPanelFrame(
                size: size,
                anchorRect: menuBarAnchorRect ?? fallbackMenuBarAnchorRect(on: screen),
                on: screen
            )
        }

        return NotchGeometry.windowFrame(
            size: size,
            on: screen,
            style: preferences.appearanceStyle
        )
    }

    private func fallbackMenuBarAnchorRect(on screen: NSScreen) -> NSRect {
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let size = CGSize(width: 28, height: menuBarHeight)
        return NSRect(
            x: screen.visibleFrame.maxX - size.width - 16,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func startMenuBarDismissMonitoring() {
        guard menuBarDismissEventMonitor == nil else { return }

        menuBarDismissEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissMenuBarPanelForExternalInteraction()
            }
        }
    }

    private func stopMenuBarDismissMonitoring() {
        guard let menuBarDismissEventMonitor else { return }

        NSEvent.removeMonitor(menuBarDismissEventMonitor)
        self.menuBarDismissEventMonitor = nil
    }

    private func dismissMenuBarPanelForExternalInteraction() {
        guard preferences.panelActivationMode == .menuBarIcon, isMenuBarPanelVisible else { return }
        hideMenuBarPanel(animated: true)
    }
}
