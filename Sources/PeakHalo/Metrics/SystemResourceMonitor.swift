import Foundation

final class SystemResourceMonitor {
    private let cpuSampler = CPUUsageSampler()
    private let memorySampler = MemoryUsageSampler()
    private let networkSampler = NetworkUsageSampler()
    private let storageSampler = StorageUsageSampler()
    private let batterySampler = BatteryUsageSampler()
    private let gpuCollector = GPUMetricsCollector()
    private let hardwareSensorsProvider: HardwareSensorsProvider

    private var lastStats = SystemResourceStats.empty
    private var lastRefreshDates: [SampleKind: Date] = [:]

    init(hardwareSensorsProvider: HardwareSensorsProvider = DefaultHardwareSensorsProvider()) {
        self.hardwareSensorsProvider = hardwareSensorsProvider
    }

    func sample(forceAll: Bool = false) -> SystemResourceStats {
        let now = Date()
        let shouldSampleCPU = due(.cpu, at: now, forceAll: forceAll)
        let shouldSampleGPU = due(.gpu, at: now, forceAll: forceAll)
        let shouldSampleMemory = due(.memory, at: now, forceAll: forceAll)
        let shouldSampleNetwork = due(.network, at: now, forceAll: forceAll)
        let shouldSampleStorage = due(.storage, at: now, forceAll: forceAll)
        let shouldSampleBattery = due(.battery, at: now, forceAll: forceAll)
        let shouldSampleHardware = due(.hardware, at: now, forceAll: forceAll)

        let cpu = shouldSampleCPU ? cpuSampler.sample() : nil
        let gpu = shouldSampleGPU ? gpuCollector.collect() : lastStats.gpu
        let memory = shouldSampleMemory ? memorySampler.sample() : lastStats.memory
        let network = shouldSampleNetwork ? networkSampler.sample(at: now) : lastStats.network
        let storage = shouldSampleStorage ? storageSampler.sample() : lastStats.storage
        let battery = shouldSampleBattery ? batterySampler.sample() : lastStats.battery
        let sensors = shouldSampleHardware
            ? hardwareSensorsProvider.sampleHardwareSensors()
            : lastStats.sensors

        let stats = SystemResourceStats(
            cpu: cpu ?? lastStats.cpu,
            gpu: gpu,
            memory: memory,
            network: network,
            storage: storage,
            battery: battery,
            sensors: sensors,
            timestamp: now
        )
        lastStats = stats
        return stats
    }
}

private enum SampleKind {
    case cpu
    case gpu
    case memory
    case network
    case storage
    case battery
    case hardware

    var interval: TimeInterval {
        switch self {
        case .cpu, .network:
            1
        case .gpu:
            2
        case .memory:
            3
        case .battery:
            5
        case .storage, .hardware:
            10
        }
    }
}

private extension SystemResourceMonitor {
    func due(_ kind: SampleKind, at date: Date, forceAll: Bool) -> Bool {
        if forceAll {
            lastRefreshDates[kind] = date
            return true
        }

        guard let lastDate = lastRefreshDates[kind] else {
            lastRefreshDates[kind] = date
            return true
        }

        guard date.timeIntervalSince(lastDate) >= kind.interval else {
            return false
        }

        lastRefreshDates[kind] = date
        return true
    }
}
