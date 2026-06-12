import AppKit
import SwiftUI

struct DashboardMetricsSection: View {
    @ObservedObject var metricsService: SystemMetricsService
    @State private var selectedResource: ResourceMonitorKind = .cpu
    @State private var forceQuitItem: ProcessResourceItem?

    private var snapshot: SystemMetricsSnapshot {
        metricsService.snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(ResourceMonitorKind.allCases) { resource in
                    Button {
                        selectedResource = resource
                    } label: {
                        DashboardResourceCard(
                            resource: resource,
                            value: value(for: resource),
                            caption: caption(for: resource),
                            history: history(for: resource),
                            isSelected: selectedResource == resource
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            DashboardResourceExpansion(
                resource: selectedResource,
                details: details(for: selectedResource),
                items: processItems(for: selectedResource),
                valueTitle: processValueTitle(for: selectedResource),
                value: processValueFormatter(for: selectedResource),
                onTerminate: { metricsService.terminate($0, force: false) },
                onForceTerminate: { forceQuitItem = $0 }
            )

            if let result = metricsService.lastKillResult {
                Label(result.message, systemImage: result.success ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(result.success ? .green : .orange)
            }
        }
        .confirmationDialog(
            "Force Quit App",
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

    private func caption(for resource: ResourceMonitorKind) -> String {
        switch resource {
        case .cpu:
            guard let cpu = snapshot.stats.cpu else { return String(localized: "Waiting for next sample") }
            return "User \(MetricFormat.percent(cpu.user)) · System \(MetricFormat.percent(cpu.system))"
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

private struct DashboardResourceCard: View {
    let resource: ResourceMonitorKind
    let value: String
    let caption: String
    let history: [Double]
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: resource.symbol)
                    .foregroundStyle(resource.tint)
                Text(resource.title)
                    .font(.headline)
                Spacer()
                Image(systemName: isSelected ? "chevron.down.circle.fill" : "chevron.right.circle")
                    .foregroundStyle(isSelected ? resource.tint : .secondary)
            }

            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if history.isEmpty {
                Spacer(minLength: 42)
            } else {
                MetricMiniGraph(data: history, color: resource.tint)
                    .frame(height: 42)
            }

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? resource.tint.opacity(0.72) : .clear, lineWidth: 1.2)
                )
        )
    }
}

private struct DashboardResourceExpansion: View {
    let resource: ResourceMonitorKind
    let details: [(LocalizedStringKey, String)]
    let items: [ProcessResourceItem]
    let valueTitle: LocalizedStringKey
    let value: (ProcessResourceItem) -> String
    let onTerminate: (ProcessResourceItem) -> Void
    let onForceTerminate: (ProcessResourceItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Label(resource.title, systemImage: resource.symbol)
                    .font(.headline)
                    .foregroundStyle(resource.tint)

                ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                    HStack {
                        Text(detail.0)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(detail.1)
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .frame(width: 250, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("App Usage")
                        .font(.headline)
                    Spacer()
                    Text(valueTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if resource.supportsAppList {
                    if items.isEmpty {
                        Text("No app samples yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(Array(items.prefix(8))) { item in
                                DashboardProcessRow(
                                    item: item,
                                    value: value(item),
                                    onTerminate: { onTerminate(item) },
                                    onForceTerminate: { onForceTerminate(item) }
                                )
                            }
                        }
                    }
                } else {
                    Text("App-level usage is not available for this resource.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct DashboardProcessRow: View {
    let item: ProcessResourceItem
    let value: String
    let onTerminate: () -> Void
    let onForceTerminate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProcessIconView(icon: item.icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(item.processCount > 1 ? String(format: String(localized: "%d processes"), item.processCount) : "PID \(item.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)

            HStack(spacing: 2) {
                ProcessActionButton(
                    symbol: "xmark.circle",
                    color: item.canTerminate ? .secondary : .secondary.opacity(0.35),
                    isEnabled: item.canTerminate,
                    help: "Quit",
                    action: onTerminate
                )

                ProcessActionButton(
                    symbol: "exclamationmark.octagon",
                    color: item.canTerminate ? .red : .secondary.opacity(0.35),
                    isEnabled: item.canTerminate,
                    help: "Force Quit",
                    action: onForceTerminate
                )
            }
            .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 3)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18, height: 18, alignment: .center)
        }
        .buttonStyle(.borderless)
        .frame(width: 23, height: 23, alignment: .center)
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
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
