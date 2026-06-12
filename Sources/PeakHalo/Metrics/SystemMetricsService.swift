import Combine
import Foundation

struct MetricReading: Equatable {
    let percent: Double?
    let label: String

    static func available(_ percent: Double, label: String) -> MetricReading {
        MetricReading(percent: min(max(percent, 0), 100), label: label)
    }

    static func unavailable(label: String) -> MetricReading {
        MetricReading(percent: nil, label: label)
    }
}

struct SystemMetricsSnapshot: Equatable {
    let cpu: MetricReading
    let gpu: MetricReading
    let memory: MetricReading
    let networkDownload: MetricReading
    let networkUpload: MetricReading
    let storage: MetricReading
    let battery: MetricReading
    let temperature: MetricReading
    let fan: MetricReading
    let stats: SystemResourceStats
    let updatedAt: Date

    static let zero = SystemMetricsSnapshot(
        cpu: .available(0, label: "CPU"),
        gpu: .unavailable(label: "GPU"),
        memory: .available(0, label: "Memory"),
        networkDownload: .unavailable(label: "Download"),
        networkUpload: .unavailable(label: "Upload"),
        storage: .unavailable(label: "Storage"),
        battery: .unavailable(label: "Battery"),
        temperature: .unavailable(label: "Temperature"),
        fan: .unavailable(label: "Fan"),
        stats: .empty,
        updatedAt: .distantPast
    )
}

@MainActor
final class SystemMetricsService: ObservableObject {
    static let shared = SystemMetricsService()

    @Published private(set) var snapshot: SystemMetricsSnapshot = .zero
    @Published private(set) var cpuHistory = MetricHistory(capacity: 30)
    @Published private(set) var gpuHistory = MetricHistory(capacity: 30)
    @Published private(set) var memoryHistory = MetricHistory(capacity: 30)
    @Published private(set) var storageHistory = MetricHistory(capacity: 30)
    @Published private(set) var batteryHistory = MetricHistory(capacity: 30)
    @Published private(set) var topCPUProcesses: [ProcessResourceItem] = []
    @Published private(set) var topMemoryProcesses: [ProcessResourceItem] = []
    @Published var lastKillResult: AppKillResult?

    private var timer: Timer?
    private let monitor = SystemResourceMonitor()
    private let processMonitor = ProcessMonitor()
    private let appKiller = AppKiller()
    private var lastProcessSampleDate: Date?

    private init() {}

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard timer == nil else { return }

        update()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.update()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func update() {
        let stats = monitor.sample(forceAll: snapshot.updatedAt == .distantPast)
        let cpuPercent = stats.cpu?.total ?? snapshot.cpu.percent ?? 0
        let memoryPercent = stats.memory.usagePercent
        let gpuPercent = stats.gpu.usage
        let storagePercent = stats.storage?.usagePercent
        let batteryPercent = stats.battery?.level

        cpuHistory.append(cpuPercent)
        memoryHistory.append(memoryPercent)
        gpuHistory.append(gpuPercent ?? 0)
        storageHistory.append(storagePercent ?? snapshot.storage.percent ?? 0)
        batteryHistory.append(batteryPercent ?? snapshot.battery.percent ?? 0)

        updateProcessesIfNeeded()

        snapshot = SystemMetricsSnapshot(
            cpu: .available(cpuPercent, label: "CPU"),
            gpu: gpuPercent.map { .available($0, label: "GPU") } ?? .unavailable(label: "GPU"),
            memory: .available(memoryPercent, label: "Memory"),
            networkDownload: stats.network.downloadBytesPerSecond.map {
                MetricReading.available(0, label: MetricFormat.rate($0))
            } ?? .unavailable(label: "Download"),
            networkUpload: stats.network.uploadBytesPerSecond.map {
                MetricReading.available(0, label: MetricFormat.rate($0))
            } ?? .unavailable(label: "Upload"),
            storage: storagePercent.map { .available($0, label: "Storage") } ?? .unavailable(label: "Storage"),
            battery: batteryPercent.map { .available($0, label: "Battery") } ?? .unavailable(label: "Battery"),
            temperature: stats.sensors.cpuTemperatureCelsius.map {
                MetricReading.available(0, label: MetricFormat.temperature($0))
            } ?? .unavailable(label: "Temperature"),
            fan: stats.sensors.fanSpeedRPM.map {
                MetricReading.available(0, label: MetricFormat.fanSpeed($0))
            } ?? .unavailable(label: "Fan"),
            stats: stats,
            updatedAt: stats.timestamp
        )
    }

    func terminate(_ item: ProcessResourceItem, force: Bool) {
        lastKillResult = appKiller.terminate(item, force: force)
        updateProcesses(force: true)
    }

    private func updateProcessesIfNeeded() {
        let now = Date()
        if let lastProcessSampleDate, now.timeIntervalSince(lastProcessSampleDate) < 2 {
            return
        }

        updateProcesses(force: false)
    }

    private func updateProcesses(force: Bool) {
        let now = Date()
        if !force, let lastProcessSampleDate, now.timeIntervalSince(lastProcessSampleDate) < 2 {
            return
        }

        lastProcessSampleDate = now
        let processes = processMonitor.sample()
            .filter { !ProcessProtection.isProtected(name: $0.name, bundleIdentifier: $0.bundleIdentifier) }

        topCPUProcesses = processes
            .sorted { lhs, rhs in
                if lhs.cpuUsage == rhs.cpuUsage {
                    return lhs.memoryBytes > rhs.memoryBytes
                }
                return lhs.cpuUsage > rhs.cpuUsage
            }
            .prefix(8)
            .map { $0 }

        topMemoryProcesses = processes
            .sorted { lhs, rhs in
                if lhs.memoryBytes == rhs.memoryBytes {
                    return lhs.cpuUsage > rhs.cpuUsage
                }
                return lhs.memoryBytes > rhs.memoryBytes
            }
            .prefix(8)
            .map { $0 }
    }
}
