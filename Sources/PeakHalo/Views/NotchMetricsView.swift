import AppKit
import SwiftUI

struct NotchMetricsView: View {
    let state: NotchState
    let displayLayout: NotchDisplayLayout
    @ObservedObject var metricsService: SystemMetricsService
    @ObservedObject private var preferences = DisplayPreferencesStore.shared
    @ObservedObject private var languageStore = AppLanguageStore.shared

    @State private var selectedTab: NotchMetricsTab = .monitor
    @State private var expandedResource: ResourceMonitorKind = .cpu
    @State private var forceQuitItem: ProcessResourceItem?
    @State private var mountsExpandedContent = false
    @State private var showsExpandedContent = false
    @State private var contentTransitionTask: Task<Void, Never>?
    @State private var strings = LocalizedMetricsStrings.cached(for: AppLanguageStore.shared.language)

    private var snapshot: SystemMetricsSnapshot {
        metricsService.snapshot
    }

    var body: some View {
        ZStack {
            closedContent
                .opacity(showsExpandedContent ? 0 : 1)
                .allowsHitTesting(!showsExpandedContent)

            if mountsExpandedContent {
                expandedContent
                    .opacity(showsExpandedContent ? 1 : 0)
                    .allowsHitTesting(showsExpandedContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            syncMountedContent(animated: false)
            syncProcessSamplingInterest()
        }
        .onChange(of: state) { _, _ in
            syncMountedContent(animated: true)
            syncProcessSamplingInterest()
        }
        .onChange(of: selectedTab) { _, _ in
            syncProcessSamplingInterest()
        }
        .onChange(of: expandedResource) { _, _ in
            syncProcessSamplingInterest()
        }
        .onChange(of: languageStore.language) { _, language in
            strings = LocalizedMetricsStrings.cached(for: language)
        }
        .onDisappear {
            contentTransitionTask?.cancel()
            contentTransitionTask = nil
            metricsService.setProcessSamplingResource(nil, for: .notch)
        }
    }

    private var closedContent: some View {
        Group {
            if visibleClosedResources.isEmpty {
                CollapsedMonitorPlaceholder()
            } else if displayLayout.hasPhysicalNotch {
                notchAwareClosedContent
            } else {
                ViewThatFits(in: .horizontal) {
                    compactResourceRow(resources: visibleClosedResources, showIcons: true, showTitles: true)
                        .fixedSize(horizontal: true, vertical: false)
                    compactResourceRow(resources: visibleClosedResources, showIcons: false, showTitles: true)
                        .fixedSize(horizontal: true, vertical: false)
                    compactResourceRow(resources: visibleClosedResources, showIcons: true, showTitles: false)
                        .fixedSize(horizontal: true, vertical: false)
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

    private var notchAwareClosedContent: some View {
        let resources = visibleClosedResources
        let midpoint = Int(ceil(Double(resources.count) / 2.0))
        let leftResources = Array(resources.prefix(midpoint))
        let rightResources = Array(resources.dropFirst(midpoint))

        return HStack(spacing: 0) {
            compactResourceCluster(resources: leftResources, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Spacer(minLength: 0)
                .frame(width: displayLayout.centerAvoidanceWidth)

            compactResourceCluster(resources: rightResources, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func compactResourceCluster(
        resources: [ResourceMonitorKind],
        alignment: Alignment
    ) -> some View {
        if resources.isEmpty {
            Color.clear
                .frame(width: 0, height: 1)
        } else {
            ViewThatFits(in: .horizontal) {
                compactResourceRow(resources: resources, showIcons: true, showTitles: true)
                    .fixedSize(horizontal: true, vertical: false)
                compactResourceRow(resources: resources, showIcons: false, showTitles: true)
                    .fixedSize(horizontal: true, vertical: false)
                compactResourceRow(resources: resources, showIcons: true, showTitles: false)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: NotchDisplayLayout.closedSideContentWidth, alignment: alignment)
        }
    }

    private func compactResourceRow(
        resources: [ResourceMonitorKind],
        showIcons: Bool,
        showTitles: Bool
    ) -> some View {
        HStack(spacing: showIcons ? 8 : 7) {
            ForEach(resources) { resource in
                CompactMetricBadge(
                    title: strings.resourceTitle(resource),
                    symbol: compactSymbol(for: resource),
                    color: resource.tint,
                    value: value(for: resource),
                    showIcon: showIcons,
                    showTitle: showTitles
                )
            }
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            NotchHeaderTabs(
                selectedTab: $selectedTab,
                monitorLayoutStyle: $preferences.monitorLayoutStyle,
                strings: strings
            )
                .frame(maxWidth: .infinity)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(12)
        .confirmationDialog(
            Text(strings.text("Force Quit App")),
            isPresented: forceQuitDialogBinding,
            titleVisibility: .visible,
            presenting: forceQuitItem
        ) { item in
            Button(strings.text("Force Quit"), role: .destructive) {
                metricsService.terminate(item, force: true)
            }
            Button(strings.text("Cancel"), role: .cancel) {}
        } message: { item in
            Text(strings.formatted(
                "Force quitting %@ may lose unsaved work.",
                arguments: [item.name]
            ))
        }
    }

    private func syncMountedContent(animated: Bool) {
        contentTransitionTask?.cancel()
        contentTransitionTask = nil

        switch state {
        case .open:
            mountsExpandedContent = true

            if animated {
                showsExpandedContent = false
                contentTransitionTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(70))
                    guard !Task.isCancelled else { return }

                    withAnimation(.easeOut(duration: 0.16)) {
                        showsExpandedContent = true
                    }
                }
            } else {
                showsExpandedContent = true
            }

        case .closed:
            if animated {
                withAnimation(.easeInOut(duration: 0.10)) {
                    showsExpandedContent = false
                }

                contentTransitionTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(110))
                    guard !Task.isCancelled else { return }
                    mountsExpandedContent = false
                }
            } else {
                showsExpandedContent = false
                mountsExpandedContent = false
            }
        }
    }

    private func syncProcessSamplingInterest() {
        let resource = state == .open && selectedTab == .monitor && expandedResource.supportsAppList
            ? expandedResource
            : nil
        metricsService.setProcessSamplingResource(resource, for: .notch)
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

            ResourceDetailPanel(
                resource: expandedResource,
                details: details(for: expandedResource),
                history: history(for: expandedResource),
                items: processItems(for: expandedResource),
                valueTitle: processValueTitle(for: expandedResource),
                value: processValueFormatter(for: expandedResource),
                isCompact: false,
                strings: strings,
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

            ResourceDetailPanel(
                resource: expandedResource,
                details: details(for: expandedResource),
                history: history(for: expandedResource),
                items: processItems(for: expandedResource),
                valueTitle: processValueTitle(for: expandedResource),
                value: processValueFormatter(for: expandedResource),
                isCompact: true,
                strings: strings,
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
                title: strings.resourceTitle(resource),
                value: value(for: resource),
                caption: caption(for: resource),
                history: history(for: resource),
                isSelected: expandedResource == resource
            )
        }
        .buttonStyle(.plain)
        .help(Text(strings.resourceTitle(resource)))
    }

    private var resourceSummaryList: some View {
        VStack(spacing: 5) {
            ForEach(ResourceMonitorKind.allCases) { resource in
                Button {
                    expandedResource = resource
                } label: {
                    CompactResourceStatRow(
                        resource: resource,
                        title: strings.resourceTitle(resource),
                        value: value(for: resource),
                        caption: caption(for: resource),
                        isSelected: expandedResource == resource
                    )
                }
                .buttonStyle(.plain)
                .help(Text(strings.resourceTitle(resource)))
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
            return strings.text("Waiting for next sample")
        case .gpu:
            return "Render \(MetricFormat.percent(snapshot.stats.gpu.renderUsage)) · VRAM \(MetricFormat.bytes(snapshot.stats.gpu.usedMemoryBytes))"
        case .memory:
            return "\(MetricFormat.bytes(snapshot.stats.memory.usedBytes)) / \(MetricFormat.bytes(snapshot.stats.memory.totalBytes))"
        case .network:
            return "↑ \(MetricFormat.rate(snapshot.stats.network.uploadBytesPerSecond))"
        case .storage:
            return strings.formatted("%@ free", arguments: [MetricFormat.bytes(snapshot.stats.storage?.freeBytes)])
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

    private func details(for resource: ResourceMonitorKind) -> [(String, String)] {
        switch resource {
        case .cpu:
            return [
                (strings.text("User"), MetricFormat.percent(snapshot.stats.cpu?.user)),
                (strings.text("System"), MetricFormat.percent(snapshot.stats.cpu?.system)),
                (strings.text("Idle"), MetricFormat.percent(snapshot.stats.cpu?.idle))
            ]
        case .gpu:
            return [
                (strings.text("Render"), MetricFormat.percent(snapshot.stats.gpu.renderUsage)),
                (strings.text("Tiler"), MetricFormat.percent(snapshot.stats.gpu.tilerUsage)),
                (strings.text("VRAM"), MetricFormat.bytes(snapshot.stats.gpu.usedMemoryBytes)),
                (strings.text("Model"), snapshot.stats.gpu.deviceName ?? "--")
            ]
        case .memory:
            return [
                (strings.text("App"), MetricFormat.bytes(snapshot.stats.memory.appBytes)),
                (strings.text("Wired"), MetricFormat.bytes(snapshot.stats.memory.wiredBytes)),
                (strings.text("Cached"), MetricFormat.bytes(snapshot.stats.memory.cachedBytes))
            ]
        case .network:
            return [
                (strings.text("Download"), MetricFormat.rate(snapshot.stats.network.downloadBytesPerSecond)),
                (strings.text("Upload"), MetricFormat.rate(snapshot.stats.network.uploadBytesPerSecond)),
                (strings.text("Received"), MetricFormat.bytes(snapshot.stats.network.receivedBytes)),
                (strings.text("Sent"), MetricFormat.bytes(snapshot.stats.network.sentBytes))
            ]
        case .storage:
            return [
                (strings.text("Used"), MetricFormat.bytes(snapshot.stats.storage?.usedBytes)),
                (strings.text("Free"), MetricFormat.bytes(snapshot.stats.storage?.freeBytes)),
                (strings.text("Total"), MetricFormat.bytes(snapshot.stats.storage?.totalBytes))
            ]
        case .battery:
            return [
                (strings.text("State"), batteryStateText),
                (strings.text("Cycles"), snapshot.stats.battery?.cycleCount.map(String.init) ?? "--"),
                (strings.text("Health"), snapshot.stats.battery?.health ?? "--"),
                (strings.text("Temperature"), MetricFormat.temperature(snapshot.stats.battery?.temperatureCelsius)),
                (strings.text("Power"), MetricFormat.power(snapshot.stats.battery?.powerWatts))
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

    private func processValueTitle(for resource: ResourceMonitorKind) -> String {
        switch resource {
        case .cpu:
            strings.resourceTitle(.cpu)
        case .memory:
            strings.resourceTitle(.memory)
        case .gpu, .network, .storage, .battery:
            strings.text("Apps")
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
            return strings.text("Charging")
        }
        if battery.isPluggedIn == true {
            return strings.text("Plugged In")
        }
        return strings.text("On Battery")
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
    let strings: LocalizedMetricsStrings

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
                    .help(Text(strings.tabTitle(tab)))
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.08), in: Capsule())

            Spacer(minLength: 0)

            if selectedTab == .monitor {
                MonitorLayoutSwitcher(selection: $monitorLayoutStyle, strings: strings)
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
            .help(strings.text("Settings"))
        }
        .frame(height: 28)
    }
}

private struct MonitorLayoutSwitcher: View {
    @Binding var selection: MonitorLayoutStyle
    let strings: LocalizedMetricsStrings

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
                .help(Text(strings.layoutTitle(style)))
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}

private struct ResourceMetricCard: View {
    let resource: ResourceMonitorKind
    let title: String
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
                Text(title)
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

private struct ResourceDetailPanel: View {
    let resource: ResourceMonitorKind
    let details: [(String, String)]
    let history: [Double]
    let items: [ProcessResourceItem]
    let valueTitle: String
    let value: (ProcessResourceItem) -> String
    let isCompact: Bool
    let strings: LocalizedMetricsStrings
    let onTerminate: (ProcessResourceItem) -> Void
    let onForceTerminate: (ProcessResourceItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(strings.resourceTitle(resource), systemImage: resource.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(resource.tint)
                Spacer()
                if resource.supportsAppList {
                    Label(strings.text("App Usage"), systemImage: "app.badge")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                    Label(strings.text("System-level data"), systemImage: "info.circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(Array(details.prefix(isCompact ? 4 : 6).enumerated()), id: \.offset) { _, detail in
                    ResourceDetailChip(title: detail.0, value: detail.1)
                }
            }

            if resource.supportsAppList {
                appUsageContent
            } else {
                systemMetricContent
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CardBackground())
    }

    private var appUsageContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(strings.text("App Usage"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Text(valueTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.48))
            }

            if items.isEmpty {
                Text(strings.text("No app samples yet"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 42 : 72, alignment: .center)
            } else {
                ScrollView {
                    VStack(spacing: isCompact ? 4 : 5) {
                        ForEach(Array(items.prefix(isCompact ? 5 : 8))) { item in
                            ProcessRow(
                                item: item,
                                value: value(item),
                                strings: strings,
                                onTerminate: { onTerminate(item) },
                                onForceTerminate: { onForceTerminate(item) }
                            )
                        }
                    }
                }
                .frame(maxHeight: isCompact ? 82 : nil)
            }
        }
    }

    private var systemMetricContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !history.isEmpty {
                MetricMiniGraph(data: history, color: resource.tint)
                    .frame(height: isCompact ? 24 : 34)
                    .padding(.top, 1)
            }

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(resource.tint.opacity(0.9))
                    .frame(width: 14)

                Text(strings.text("App-level usage is not available for this resource."))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ResourceDetailChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CompactResourceStatRow: View {
    let resource: ResourceMonitorKind
    let title: String
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
                Text(title)
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

private struct CompactMetricBadge: View {
    let title: String
    let symbol: String
    let color: Color
    let value: String
    let showIcon: Bool
    let showTitle: Bool

    var body: some View {
        HStack(spacing: showIcon ? 4 : 3) {
            if showIcon {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
            }

            if showTitle {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }

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
    let strings: LocalizedMetricsStrings
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

                Text(item.processCount > 1
                    ? strings.formatted("%d processes", arguments: [item.processCount])
                    : "PID \(item.pid)")
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
                    help: strings.text("Quit"),
                    action: onTerminate
                )

                ProcessActionButton(
                    symbol: "exclamationmark.octagon",
                    color: item.canTerminate ? .red.opacity(0.86) : .white.opacity(0.24),
                    isEnabled: item.canTerminate,
                    help: strings.text("Force Quit"),
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
    let help: String
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
