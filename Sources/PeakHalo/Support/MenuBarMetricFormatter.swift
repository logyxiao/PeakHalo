import Foundation

struct MenuBarMetricColumn: Equatable {
    let resource: ResourceMonitorKind
    let topText: String
    let bottomText: String

    var accessibilityText: String {
        "\(topText) \(bottomText)"
    }
}

enum MenuBarMetricFormatter {
    static func columns(
        for snapshot: SystemMetricsSnapshot,
        resources: [ResourceMonitorKind],
        localizedTitle: (String) -> String
    ) -> [MenuBarMetricColumn] {
        resources.map { resource in
            if resource == .network {
                return MenuBarMetricColumn(
                    resource: resource,
                    topText: "↑ \(MetricFormat.rate(snapshot.stats.network.uploadBytesPerSecond))",
                    bottomText: "↓ \(MetricFormat.rate(snapshot.stats.network.downloadBytesPerSecond))"
                )
            }

            return MenuBarMetricColumn(
                resource: resource,
                topText: localizedTitle(resource.titleKey),
                bottomText: value(for: resource, snapshot: snapshot)
            )
        }
    }

    static func value(for resource: ResourceMonitorKind, snapshot: SystemMetricsSnapshot) -> String {
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
}
