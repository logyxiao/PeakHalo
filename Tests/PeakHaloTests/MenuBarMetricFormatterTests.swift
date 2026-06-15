import Foundation
import Testing
@testable import PeakHalo

@Suite("Menu bar metric formatter")
struct MenuBarMetricFormatterTests {
    @Test("Columns keep resource order and use localized titles")
    func columnsKeepResourceOrderAndUseLocalizedTitles() {
        let columns = MenuBarMetricFormatter.columns(
            for: snapshot(
                cpu: 42.4,
                gpu: 12.0,
                memory: 67.2,
                networkDownloadBytesPerSecond: 1536,
                networkUploadBytesPerSecond: 2048,
                storage: 81.0,
                battery: 73.0
            ),
            resources: [.cpu, .network, .battery]
        ) { key in
            "zh-\(key)"
        }

        #expect(columns.map(\.resource) == [.cpu, .network, .battery])
        #expect(columns.map(\.topText) == ["zh-CPU", "↑ 2.0KB/s", "zh-Battery"])
        #expect(columns.map(\.bottomText) == ["42%", "↓ 1.5KB/s", "73%"])
    }

    @Test("Unavailable metrics use placeholders")
    func unavailableMetricsUsePlaceholders() {
        let columns = MenuBarMetricFormatter.columns(
            for: snapshot(
                cpu: nil,
                gpu: nil,
                memory: 0,
                networkDownloadBytesPerSecond: nil,
                networkUploadBytesPerSecond: nil,
                storage: nil,
                battery: nil
            ),
            resources: [.cpu, .gpu, .network, .storage, .battery]
        ) { $0 }

        #expect(columns.map(\.topText) == ["CPU", "GPU", "↑ --", "Storage", "Battery"])
        #expect(columns.map(\.bottomText) == ["--", "--", "↓ --", "--", "--"])
    }

    private func snapshot(
        cpu: Double?,
        gpu: Double?,
        memory: Double,
        networkDownloadBytesPerSecond: UInt64?,
        networkUploadBytesPerSecond: UInt64?,
        storage: Double?,
        battery: Double?
    ) -> SystemMetricsSnapshot {
        var stats = SystemResourceStats.empty
        stats.network = NetworkStats(
            downloadBytesPerSecond: networkDownloadBytesPerSecond,
            uploadBytesPerSecond: networkUploadBytesPerSecond,
            receivedBytes: 0,
            sentBytes: 0
        )

        return SystemMetricsSnapshot(
            cpu: cpu.map { .available($0, label: "CPU") } ?? .unavailable(label: "CPU"),
            gpu: gpu.map { .available($0, label: "GPU") } ?? .unavailable(label: "GPU"),
            memory: .available(memory, label: "Memory"),
            networkDownload: networkDownloadBytesPerSecond.map {
                .available(0, label: MetricFormat.rate($0))
            } ?? .unavailable(label: "Download"),
            networkUpload: .unavailable(label: "Upload"),
            storage: storage.map { .available($0, label: "Storage") } ?? .unavailable(label: "Storage"),
            battery: battery.map { .available($0, label: "Battery") } ?? .unavailable(label: "Battery"),
            temperature: .unavailable(label: "Temperature"),
            fan: .unavailable(label: "Fan"),
            stats: stats,
            updatedAt: Date()
        )
    }
}
