import AppKit
import Combine

@MainActor
final class MenuBarStatusItemController: NSObject {
    static let shared = MenuBarStatusItemController()

    private let preferences = DisplayPreferencesStore.shared
    private let languageStore = AppLanguageStore.shared
    private var statusItem: NSStatusItem?
    private weak var metricsService: SystemMetricsService?
    private var currentSnapshot: SystemMetricsSnapshot = .zero
    private var cancellables = Set<AnyCancellable>()
    private var metricsCancellable: AnyCancellable?
    private static let statusItemLength: CGFloat = NSStatusItem.squareLength
    private static let statusIconSize = NSSize(width: 18, height: 18)
    private static let metricsImageHeight: CGFloat = 22
    private static let metricsOuterPadding: CGFloat = 5
    private static let metricsColumnSpacing: CGFloat = 7

    private override init() {
        super.init()
        languageStore.$language
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        preferences.$panelActivationMode
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        preferences.$collapsedVisibleMonitors
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)
    }

    func start(metricsService: SystemMetricsService) {
        self.metricsService = metricsService
        currentSnapshot = metricsService.snapshot
        metricsCancellable = metricsService.$snapshot
            .sink { [weak self] snapshot in
                self?.currentSnapshot = snapshot
                self?.refreshStatusItem()
            }

        guard statusItem == nil else {
            refreshStatusItem()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: Self.statusItemLength)
        item.isVisible = true
        item.button?.image = Self.makeStatusBarIcon()
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.imagePosition = .imageOnly
        item.button?.title = ""
        item.button?.isBordered = false
        item.button?.setAccessibilityLabel(languageStore.localizedString("PeakHalo"))
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = languageStore.localizedString("PeakHalo")
        statusItem = item
        refreshStatusItem()
    }

    func stop() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        metricsCancellable?.cancel()
        metricsCancellable = nil
        metricsService = nil
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }

        switch preferences.panelActivationMode {
        case .menuBarIcon:
            NotchWindowManager.shared.toggle(fromMenuBarAnchor: statusItemAnchorRect())
        case .notchHover:
            showMenu()
        }
    }

    private func showMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        NotchWindowManager.shared.close(animated: false)

        let menu = NSMenu()
        menu.addItem(
            withTitle: languageStore.localizedString("Settings"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        menu.addItem(
            withTitle: languageStore.localizedString("Quit PeakHalo"),
            action: #selector(quit),
            keyEquivalent: "q"
        )

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func refreshStatusItem() {
        guard let statusItem, let button = statusItem.button else { return }

        let title = AppLocalization.localizedString("PeakHalo", language: languageStore.language)
        if preferences.panelActivationMode == .menuBarIcon {
            let columns = menuBarMetricColumns()
            if !columns.isEmpty {
                let image = Self.makeMetricStatusBarImage(columns: columns)
                statusItem.length = image.size.width
                button.image = image
                button.imageScaling = .scaleNone
                button.imagePosition = .imageOnly
                button.title = ""
                button.setAccessibilityLabel(metricAccessibilityTitle(title: title, columns: columns))
                button.toolTip = metricAccessibilityTitle(title: title, columns: columns)
                return
            }
        }

        statusItem.length = Self.statusItemLength
        button.image = Self.makeStatusBarIcon()
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.title = ""
        button.setAccessibilityLabel(title)
        button.toolTip = title
    }

    @objc
    private func showSettings() {
        NotchWindowManager.shared.close(animated: false)
        AppWindowPresenter.shared.showSettingsWindow()
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func statusItemAnchorRect() -> NSRect? {
        guard let button = statusItem?.button,
              let window = button.window else {
            return nil
        }

        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func menuBarMetricColumns() -> [MenuBarMetricColumn] {
        let resources = ResourceMonitorKind.allCases.filter {
            preferences.collapsedVisibleMonitors.contains($0)
        }

        return MenuBarMetricFormatter.columns(
            for: currentSnapshot,
            resources: resources
        ) { key in
            languageStore.localizedString(key)
        }
    }

    private func metricAccessibilityTitle(title: String, columns: [MenuBarMetricColumn]) -> String {
        let summary = columns
            .map(\.accessibilityText)
            .joined(separator: ", ")
        return summary.isEmpty ? title : "\(title): \(summary)"
    }

    private static func makeStatusBarIcon() -> NSImage {
        makeLogoStatusBarIcon()
    }

    private static func makeMetricStatusBarImage(columns: [MenuBarMetricColumn]) -> NSImage {
        let metricAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.8, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let columnWidths = columns.map { column in
            max(
                Self.minimumMetricColumnWidth(for: column.resource),
                Self.textWidth(column.topText, attributes: metricAttributes),
                Self.textWidth(column.bottomText, attributes: metricAttributes)
            )
        }
        let totalColumnsWidth = columnWidths.reduce(0, +)
        let spacing = CGFloat(max(columns.count - 1, 0)) * metricsColumnSpacing
        let width = ceil(metricsOuterPadding * 2 + totalColumnsWidth + spacing)
        let size = NSSize(width: width, height: metricsImageHeight)

        let image = NSImage(size: size, flipped: false) { rect in
            var x = metricsOuterPadding
            for (index, column) in columns.enumerated() {
                let columnWidth = columnWidths[index]
                Self.drawCentered(
                    column.topText,
                    attributes: metricAttributes,
                    x: x,
                    y: rect.maxY - 10.2,
                    width: columnWidth
                )
                Self.drawCentered(
                    column.bottomText,
                    attributes: metricAttributes,
                    x: x,
                    y: 1.6,
                    width: columnWidth
                )
                x += columnWidth + metricsColumnSpacing
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = AppLocalization.localizedString("PeakHalo", language: .system)
        return image
    }

    private static func minimumMetricColumnWidth(for resource: ResourceMonitorKind) -> CGFloat {
        switch resource {
        case .network:
            58
        case .storage:
            34
        case .memory:
            38
        case .battery:
            36
        case .cpu, .gpu:
            30
        }
    }

    private static func textWidth(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private static func drawCentered(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) {
        let textSize = (text as NSString).size(withAttributes: attributes)
        let textX = x + max(0, (width - textSize.width) / 2)
        (text as NSString).draw(
            at: NSPoint(x: textX, y: y),
            withAttributes: attributes
        )
    }

    private static func makeLogoStatusBarIcon() -> NSImage {
        let size = statusIconSize
        let image = NSImage(size: size, flipped: false) { rect in
            let strokeColor = NSColor.black.withAlphaComponent(0.92)
            strokeColor.setStroke()
            strokeColor.setFill()

            let haloPath = NSBezierPath()
            haloPath.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY - 0.3),
                radius: 5.15,
                startAngle: 36,
                endAngle: 326
            )
            haloPath.lineWidth = 1.7
            haloPath.lineCapStyle = .round
            haloPath.stroke()

            let notchRect = NSRect(x: rect.midX - 2.2, y: rect.maxY - 4.9, width: 4.4, height: 1.5)
            let notchPath = NSBezierPath(roundedRect: notchRect, xRadius: 0.75, yRadius: 0.75)
            notchPath.fill()

            let pulsePath = NSBezierPath()
            pulsePath.lineWidth = 1.45
            pulsePath.lineCapStyle = .round
            pulsePath.lineJoinStyle = .round
            pulsePath.move(to: NSPoint(x: rect.midX - 2.6, y: rect.midY - 0.8))
            pulsePath.line(to: NSPoint(x: rect.midX - 1.0, y: rect.midY - 0.8))
            pulsePath.line(to: NSPoint(x: rect.midX - 0.1, y: rect.midY + 0.9))
            pulsePath.line(to: NSPoint(x: rect.midX + 1.0, y: rect.midY - 1.8))
            pulsePath.line(to: NSPoint(x: rect.midX + 2.2, y: rect.midY - 0.2))
            pulsePath.line(to: NSPoint(x: rect.midX + 3.4, y: rect.midY - 0.2))
            pulsePath.stroke()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppLocalization.localizedString("PeakHalo", language: .system)
        return image
    }
}
