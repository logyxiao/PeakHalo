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

enum ProcessSamplingConsumer: Hashable {
    case notch
    case dashboard
}

@MainActor
final class SystemMetricsService: NSObject, ObservableObject {
    static let shared = SystemMetricsService()

    @Published private(set) var snapshot: SystemMetricsSnapshot = .zero
    private(set) var cpuHistory = MetricHistory(capacity: 30)
    private(set) var gpuHistory = MetricHistory(capacity: 30)
    private(set) var memoryHistory = MetricHistory(capacity: 30)
    private(set) var storageHistory = MetricHistory(capacity: 30)
    private(set) var batteryHistory = MetricHistory(capacity: 30)
    @Published private(set) var topCPUProcesses: [ProcessResourceItem] = []
    @Published private(set) var topMemoryProcesses: [ProcessResourceItem] = []
    @Published var lastKillResult: AppKillResult?

    private var timer: Timer?
    private let metricsWorker = SystemMetricsWorker()
    private let processMonitor = ProcessMonitor()
    private let appKiller = AppKiller()
    private var lastProcessSampleDate: Date?
    private var isRunning = false
    private var isSamplingMetrics = false
    private var hasQueuedMetricsSample = false
    private var metricsGeneration = 0
    private var processSamplingRequests: [ProcessSamplingConsumer: ResourceMonitorKind] = [:]
    private let processSampleInterval: TimeInterval = 8
    private let processTopLimit = 8

    private override init() {
        super.init()
    }

    func start() {
        guard timer == nil else { return }

        isRunning = true
        metricsGeneration += 1
        update()
        timer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(timerDidFire(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isSamplingMetrics = false
        hasQueuedMetricsSample = false
        processSamplingRequests.removeAll()
        metricsGeneration += 1
    }

    func update() {
        scheduleMetricsSample(forceAll: snapshot.updatedAt == .distantPast)
        updateProcessesIfNeeded()
    }

    func setProcessSamplingResource(_ resource: ResourceMonitorKind?, for consumer: ProcessSamplingConsumer) {
        let previousResource = activeProcessResource

        if let resource, resource.supportsAppList {
            processSamplingRequests[consumer] = resource
        } else {
            processSamplingRequests.removeValue(forKey: consumer)
        }

        guard activeProcessResource != nil else { return }

        if previousResource == nil || previousResource != activeProcessResource {
            updateProcesses(force: true)
        } else {
            updateProcessesIfNeeded()
        }
    }

    private var activeProcessResource: ResourceMonitorKind? {
        processSamplingRequests.values.first(where: \.supportsAppList)
    }

    private func scheduleMetricsSample(forceAll: Bool) {
        guard isRunning else { return }

        if isSamplingMetrics {
            hasQueuedMetricsSample = hasQueuedMetricsSample || forceAll
            return
        }

        isSamplingMetrics = true
        let generation = metricsGeneration
        metricsWorker.sample(forceAll: forceAll) { [weak self] stats in
            guard let service = self else { return }
            Task { @MainActor in
                service.applyMetricsSample(stats, generation: generation)
            }
        }
    }

    private func applyMetricsSample(_ stats: SystemResourceStats, generation: Int) {
        guard generation == metricsGeneration, isRunning else { return }

        isSamplingMetrics = false
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

        updateProcessesIfNeeded()

        guard hasQueuedMetricsSample else { return }
        let forceAll = hasQueuedMetricsSample && snapshot.updatedAt == .distantPast
        hasQueuedMetricsSample = false
        scheduleMetricsSample(forceAll: forceAll)
    }

    @objc private func timerDidFire(_ timer: Timer) {
        update()
    }

    func terminate(_ item: ProcessResourceItem, force: Bool) {
        lastKillResult = appKiller.terminate(item, force: force)
        updateProcesses(force: true)
    }

    private func updateProcessesIfNeeded() {
        guard activeProcessResource != nil else { return }

        let now = Date()
        if topCPUProcesses.isEmpty && topMemoryProcesses.isEmpty {
            updateProcesses(force: true)
            return
        }

        if let lastProcessSampleDate, now.timeIntervalSince(lastProcessSampleDate) < processSampleInterval {
            return
        }

        updateProcesses(force: false)
    }

    private func updateProcesses(force: Bool) {
        guard force || activeProcessResource != nil else { return }

        let now = Date()
        if !force, let lastProcessSampleDate, now.timeIntervalSince(lastProcessSampleDate) < processSampleInterval {
            return
        }

        lastProcessSampleDate = now
        let processes = processMonitor.sample()
            .filter { !ProcessProtection.isProtected(name: $0.name, bundleIdentifier: $0.bundleIdentifier) }

        let topProcesses = Self.topProcesses(from: processes, limit: processTopLimit)
        topCPUProcesses = topProcesses.cpu
        topMemoryProcesses = topProcesses.memory
    }

    private static func topProcesses(
        from processes: [ProcessResourceItem],
        limit: Int
    ) -> (cpu: [ProcessResourceItem], memory: [ProcessResourceItem]) {
        var cpu: [ProcessResourceItem] = []
        var memory: [ProcessResourceItem] = []

        for process in processes {
            insert(
                process,
                into: &cpu,
                limit: limit
            ) { lhs, rhs in
                if lhs.cpuUsage == rhs.cpuUsage {
                    return lhs.memoryBytes > rhs.memoryBytes
                }
                return lhs.cpuUsage > rhs.cpuUsage
            }

            insert(
                process,
                into: &memory,
                limit: limit
            ) { lhs, rhs in
                if lhs.memoryBytes == rhs.memoryBytes {
                    return lhs.cpuUsage > rhs.cpuUsage
                }
                return lhs.memoryBytes > rhs.memoryBytes
            }
        }

        return (cpu, memory)
    }

    private static func insert(
        _ process: ProcessResourceItem,
        into processes: inout [ProcessResourceItem],
        limit: Int,
        sortedBy areInIncreasingOrder: (ProcessResourceItem, ProcessResourceItem) -> Bool
    ) {
        processes.append(process)
        processes.sort(by: areInIncreasingOrder)
        if processes.count > limit {
            processes.removeLast(processes.count - limit)
        }
    }
}

private final class SystemMetricsWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "peakhalo.system-metrics", qos: .utility)
    private let monitor = SystemResourceMonitor()

    func sample(forceAll: Bool, completion: @escaping @Sendable (SystemResourceStats) -> Void) {
        queue.async {
            completion(self.monitor.sample(forceAll: forceAll))
        }
    }
}
