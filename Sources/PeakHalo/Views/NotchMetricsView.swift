import AppKit
import SwiftUI

struct NotchMetricsView: View {
    let state: NotchState
    @ObservedObject var metricsService: SystemMetricsService
    @ObservedObject private var preferences = DisplayPreferencesStore.shared

    @State private var selectedTab: NotchMetricsTab = .monitor
    @State private var expandedResource: ResourceMonitorKind = .cpu
    @State private var forceQuitItem: ProcessResourceItem?

    private var snapshot: SystemMetricsSnapshot {
        metricsService.snapshot
    }

    var body: some View {
        switch state {
        case .closed:
            closedContent
        case .open:
            expandedContent
        }
    }

    private var closedContent: some View {
        Group {
            if visibleClosedResources.isEmpty {
                CollapsedMonitorPlaceholder()
            } else {
                ViewThatFits(in: .horizontal) {
                    compactResourceRow(showIcons: true)
                        .fixedSize(horizontal: true, vertical: false)
                    compactResourceRow(showIcons: false)
                        .fixedSize(horizontal: true, vertical: false)
                    compactResourceRow(showIcons: false)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var visibleClosedResources: [ResourceMonitorKind] {
        return ResourceMonitorKind.allCases.filter {
            preferences.collapsedVisibleMonitors.contains($0)
        }
    }

    private func compactResourceRow(showIcons: Bool) -> some View {
        HStack(spacing: showIcons ? 8 : 7) {
            ForEach(visibleClosedResources) { resource in
                CompactMetricBadge(
                    title: resource.title,
                    symbol: compactSymbol(for: resource),
                    color: resource.tint,
                    value: value(for: resource),
                    showIcon: showIcons
                )
            }
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            NotchHeaderTabs(
                selectedTab: $selectedTab,
                monitorLayoutStyle: $preferences.monitorLayoutStyle
            )
                .frame(maxWidth: .infinity)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(12)
        .confirmationDialog(
            Text("Force Quit App"),
            isPresented: forceQuitDialogBinding,
            titleVisibility: .visible,
            presenting: forceQuitItem
        ) { item in
            Button("Force Quit", role: .destructive) {
                metricsService.terminate(item, force: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(String(format: String(localized: "Force quitting %@ may lose unsaved work."), item.name))
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .monitor:
                monitorTab
            case .battery:
                BatteryDevicesView(compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .audio:
                AudioControlsView(compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .controls:
                DisplayControlsView(compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var monitorTab: some View {
        Group {
            switch preferences.monitorLayoutStyle {
            case .split:
                splitMonitorLayout
            case .cards:
                cardMonitorLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var splitMonitorLayout: some View {
        HStack(alignment: .top, spacing: 10) {
            resourceSummaryList

            ResourceAppUsagePanel(
                resource: expandedResource,
                items: processItems(for: expandedResource),
                valueTitle: processValueTitle(for: expandedResource),
                value: processValueFormatter(for: expandedResource),
                onTerminate: { metricsService.terminate($0, force: false) },
                onForceTerminate: { forceQuitItem = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var cardMonitorLayout: some View {
        VStack(spacing: 8) {
            resourceGrid

            ResourceExpansionPanel(
                resource: expandedResource,
                details: details(for: expandedResource),
                items: processItems(for: expandedResource),
                valueTitle: processValueTitle(for: expandedResource),
                value: processValueFormatter(for: expandedResource),
                onTerminate: { metricsService.terminate($0, force: false) },
                onForceTerminate: { forceQuitItem = $0 }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var resourceGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                resourceCard(.cpu)
                resourceCard(.gpu)
                resourceCard(.memory)
            }
            HStack(spacing: 8) {
                resourceCard(.network)
                resourceCard(.storage)
                resourceCard(.battery)
            }
        }
    }

    private func resourceCard(_ resource: ResourceMonitorKind) -> some View {
        Button {
            expandedResource = resource
        } label: {
            ResourceMetricCard(
                resource: resource,
                value: value(for: resource),
                caption: caption(for: resource),
                history: history(for: resource),
                isSelected: expandedResource == resource
            )
        }
        .buttonStyle(.plain)
        .help(Text(resource.title))
    }

    private var resourceSummaryList: some View {
        VStack(spacing: 5) {
            ForEach(ResourceMonitorKind.allCases) { resource in
                Button {
                    expandedResource = resource
                } label: {
                    CompactResourceStatRow(
                        resource: resource,
                        value: value(for: resource),
                        caption: caption(for: resource),
                        isSelected: expandedResource == resource
                    )
                }
                .buttonStyle(.plain)
                .help(Text(resource.title))
            }
        }
        .padding(8)
        .frame(width: 226, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(CardBackground())
    }

    private func value(for resource: ResourceMonitorKind) -> String {
        switch resource {
        case .cpu:
            MetricFormat.percent(snapshot.cpu.percent)
        case .gpu:
            MetricFormat.percent(snapshot.gpu.percent)
        case .memory:
            MetricFormat.percent(snapshot.memory.percent)
        case .network:
            "↓ \(MetricFormat.rate(snapshot.stats.network.downloadBytesPerSecond))"
        case .storage:
            MetricFormat.percent(snapshot.storage.percent)
        case .battery:
            MetricFormat.percent(snapshot.battery.percent)
        }
    }

    private func compactSymbol(for resource: ResourceMonitorKind) -> String {
        switch resource {
        case .network:
            "arrow.down"
        default:
            resource.symbol
        }
    }

    private func caption(for resource: ResourceMonitorKind) -> String {
        switch resource {
        case .cpu:
            if let cpu = snapshot.stats.cpu {
                return "User \(MetricFormat.percent(cpu.user)) · System \(MetricFormat.percent(cpu.system))"
            }
            return String(localized: "Waiting for next sample")
        case .gpu:
            return "Render \(MetricFormat.percent(snapshot.stats.gpu.renderUsage)) · VRAM \(MetricFormat.bytes(snapshot.stats.gpu.usedMemoryBytes))"
        case .memory:
            return "\(MetricFormat.bytes(snapshot.stats.memory.usedBytes)) / \(MetricFormat.bytes(snapshot.stats.memory.totalBytes))"
        case .network:
            return "↑ \(MetricFormat.rate(snapshot.stats.network.uploadBytesPerSecond))"
        case .storage:
            return String(
                format: String(localized: "%@ free"),
                MetricFormat.bytes(snapshot.stats.storage?.freeBytes)
            )
        case .battery:
            return batteryStateText
        }
    }

    private func history(for resource: ResourceMonitorKind) -> [Double] {
        switch resource {
        case .cpu:
            metricsService.cpuHistory.values
        case .gpu:
            metricsService.gpuHistory.values
        case .memory:
            metricsService.memoryHistory.values
        case .network:
            []
        case .storage:
            metricsService.storageHistory.values
        case .battery:
            metricsService.batteryHistory.values
        }
    }

    private func details(for resource: ResourceMonitorKind) -> [(LocalizedStringKey, String)] {
        switch resource {
        case .cpu:
            return [
                ("User", MetricFormat.percent(snapshot.stats.cpu?.user)),
                ("System", MetricFormat.percent(snapshot.stats.cpu?.system)),
                ("Idle", MetricFormat.percent(snapshot.stats.cpu?.idle))
            ]
        case .gpu:
            return [
                ("Render", MetricFormat.percent(snapshot.stats.gpu.renderUsage)),
                ("Tiler", MetricFormat.percent(snapshot.stats.gpu.tilerUsage)),
                ("VRAM", MetricFormat.bytes(snapshot.stats.gpu.usedMemoryBytes)),
                ("Model", snapshot.stats.gpu.deviceName ?? "--")
            ]
        case .memory:
            return [
                ("App", MetricFormat.bytes(snapshot.stats.memory.appBytes)),
                ("Wired", MetricFormat.bytes(snapshot.stats.memory.wiredBytes)),
                ("Compressed", MetricFormat.bytes(snapshot.stats.memory.compressedBytes)),
                ("Cached", MetricFormat.bytes(snapshot.stats.memory.cachedBytes)),
                ("Swap", MetricFormat.bytes(snapshot.stats.memory.swapUsedBytes))
            ]
        case .network:
            return [
                ("Download", MetricFormat.rate(snapshot.stats.network.downloadBytesPerSecond)),
                ("Upload", MetricFormat.rate(snapshot.stats.network.uploadBytesPerSecond)),
                ("Received", MetricFormat.bytes(snapshot.stats.network.receivedBytes)),
                ("Sent", MetricFormat.bytes(snapshot.stats.network.sentBytes))
            ]
        case .storage:
            return [
                ("Used", MetricFormat.bytes(snapshot.stats.storage?.usedBytes)),
                ("Free", MetricFormat.bytes(snapshot.stats.storage?.freeBytes)),
                ("Total", MetricFormat.bytes(snapshot.stats.storage?.totalBytes))
            ]
        case .battery:
            return [
                ("State", batteryStateText),
                ("Cycles", snapshot.stats.battery?.cycleCount.map(String.init) ?? "--"),
                ("Health", snapshot.stats.battery?.health ?? "--"),
                ("Temperature", MetricFormat.temperature(snapshot.stats.battery?.temperatureCelsius)),
                ("Power", MetricFormat.power(snapshot.stats.battery?.powerWatts))
            ]
        }
    }

    private func processItems(for resource: ResourceMonitorKind) -> [ProcessResourceItem] {
        switch resource {
        case .cpu:
            metricsService.topCPUProcesses
        case .memory:
            metricsService.topMemoryProcesses
        case .gpu, .network, .storage, .battery:
            []
        }
    }

    private func processValueTitle(for resource: ResourceMonitorKind) -> LocalizedStringKey {
        switch resource {
        case .cpu:
            "CPU"
        case .memory:
            "Memory"
        case .gpu, .network, .storage, .battery:
            "Apps"
        }
    }

    private func processValueFormatter(for resource: ResourceMonitorKind) -> (ProcessResourceItem) -> String {
        switch resource {
        case .cpu:
            { MetricFormat.processPercent($0.cpuUsage) }
        case .memory:
            { MetricFormat.bytes($0.memoryBytes) }
        case .gpu, .network, .storage, .battery:
            { _ in "--" }
        }
    }

    private var batteryStateText: String {
        guard let battery = snapshot.stats.battery else { return "--" }
        if battery.isCharging == true {
            return String(localized: "Charging")
        }
        if battery.isPluggedIn == true {
            return String(localized: "Plugged In")
        }
        return String(localized: "On Battery")
    }

    private var forceQuitDialogBinding: Binding<Bool> {
        Binding(
            get: { forceQuitItem != nil },
            set: { isPresented in
                if !isPresented {
                    forceQuitItem = nil
                }
            }
        )
    }
}

private struct NotchHeaderTabs: View {
    @Binding var selectedTab: NotchMetricsTab
    @Binding var monitorLayoutStyle: MonitorLayoutStyle

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(NotchMetricsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? Color.black : Color.white.opacity(0.82))
                            .frame(width: 24, height: 22)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? Color.white : Color.white.opacity(0.09))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(Text(tab.title))
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.08), in: Capsule())

            Spacer(minLength: 0)

            if selectedTab == .monitor {
                MonitorLayoutSwitcher(selection: $monitorLayoutStyle)
            }

            Button {
                AppWindowPresenter.shared.showSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 28, height: 24)
                    .background(Color.white.opacity(0.09), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .frame(height: 28)
    }
}

private struct MonitorLayoutSwitcher: View {
    @Binding var selection: MonitorLayoutStyle

    var body: some View {
        HStack(spacing: 3) {
            ForEach(MonitorLayoutStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    Image(systemName: style.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == style ? Color.black : Color.white.opacity(0.78))
                        .frame(width: 25, height: 21)
                        .background(
                            Capsule()
                                .fill(selection == style ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(Text(style.localizedName))
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}

private struct ResourceMetricCard: View {
    let resource: ResourceMonitorKind
    let value: String
    let caption: String
    let history: [Double]
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: resource.symbol)
                    .font(.caption)
                    .foregroundStyle(resource.tint)
                Text(resource.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "chevron.down.circle.fill" : "chevron.right.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .white.opacity(0.34))
            }

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            if history.isEmpty {
                Text(caption)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            } else {
                MetricMiniGraph(data: history, color: resource.tint)
                    .frame(height: 16)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? resource.tint.opacity(0.2) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? resource.tint.opacity(0.72) : Color.white.opacity(0.13), lineWidth: 1)
                )
        )
    }
}

private struct ResourceExpansionPanel: View {
    let resource: ResourceMonitorKind
    let details: [(LocalizedStringKey, String)]
    let items: [ProcessResourceItem]
    let valueTitle: LocalizedStringKey
    let value: (ProcessResourceItem) -> String
    let onTerminate: (ProcessResourceItem) -> Void
    let onForceTerminate: (ProcessResourceItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Label(resource.title, systemImage: resource.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(resource.tint)

                ForEach(Array(details.prefix(5).enumerated()), id: \.offset) { _, detail in
                    HStack {
                        Text(detail.0)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.56))
                        Spacer(minLength: 8)
                        Text(detail.1)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 176, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("App Usage", systemImage: "app.badge")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text(valueTitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.48))
                }

                if resource.supportsAppList {
                    if items.isEmpty {
                        Text("No app samples yet")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    } else {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(Array(items.prefix(5))) { item in
                                    ProcessRow(
                                        item: item,
                                        value: value(item),
                                        onTerminate: { onTerminate(item) },
                                        onForceTerminate: { onForceTerminate(item) }
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 96)
                    }
                } else {
                    Text("App-level usage is not available for this resource.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CardBackground())
    }
}

private struct CompactResourceStatRow: View {
    let resource: ResourceMonitorKind
    let value: String
    let caption: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(resource.tint.opacity(isSelected ? 0.24 : 0.14))
                Image(systemName: resource.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(resource.tint)
            }
            .frame(width: 25, height: 25)

            VStack(alignment: .leading, spacing: 1) {
                Text(resource.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? resource.tint.opacity(0.18) : Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? resource.tint.opacity(0.62) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ResourceAppUsagePanel: View {
    let resource: ResourceMonitorKind
    let items: [ProcessResourceItem]
    let valueTitle: LocalizedStringKey
    let value: (ProcessResourceItem) -> String
    let onTerminate: (ProcessResourceItem) -> Void
    let onForceTerminate: (ProcessResourceItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("App Usage", systemImage: "app.badge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.84))
                Spacer()
                Label(resource.title, systemImage: resource.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(resource.tint)
                Text(valueTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.48))
            }

            if resource.supportsAppList {
                if items.isEmpty {
                    Text("No app samples yet")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(Array(items.prefix(8))) { item in
                                ProcessRow(
                                    item: item,
                                    value: value(item),
                                    onTerminate: { onTerminate(item) },
                                    onForceTerminate: { onForceTerminate(item) }
                                )
                            }
                        }
                    }
                }
            } else {
                Text("App-level usage is not available for this resource.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CardBackground())
    }
}

private struct CompactMetricBadge: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    let value: String
    let showIcon: Bool

    var body: some View {
        HStack(spacing: showIcon ? 4 : 3) {
            if showIcon {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
            }

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.76)
    }
}

private struct CollapsedMonitorPlaceholder: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.white.opacity(0.68))
                .frame(width: 5, height: 5)
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 28, height: 4)
            Circle()
                .fill(Color.white.opacity(0.44))
                .frame(width: 5, height: 5)
        }
        .frame(minWidth: 58, minHeight: 14)
        .accessibilityLabel(Text("Dynamic Island"))
    }
}

private struct ProcessRow: View {
    let item: ProcessResourceItem
    let value: String
    let onTerminate: () -> Void
    let onForceTerminate: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            ProcessIconView(icon: item.icon)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.processCount > 1 ? String(format: String(localized: "%d processes"), item.processCount) : "PID \(item.pid)")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 2) {
                ProcessActionButton(
                    symbol: "xmark.circle",
                    color: .white.opacity(item.canTerminate ? 0.78 : 0.26),
                    isEnabled: item.canTerminate,
                    help: "Quit",
                    action: onTerminate
                )

                ProcessActionButton(
                    symbol: "exclamationmark.octagon",
                    color: item.canTerminate ? .red.opacity(0.86) : .white.opacity(0.24),
                    isEnabled: item.canTerminate,
                    help: "Force Quit",
                    action: onForceTerminate
                )
            }
            .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ProcessActionButton: View {
    let symbol: String
    let color: Color
    let isEnabled: Bool
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18, alignment: .center)
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22, alignment: .center)
        .contentShape(Rectangle())
        .disabled(!isEnabled)
        .help(Text(help))
    }
}

private struct ProcessIconView: View {
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
            } else {
                Image(systemName: "app")
                    .resizable()
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(3)
            }
        }
        .frame(width: 17, height: 17)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.13), lineWidth: 1)
            )
    }
}
