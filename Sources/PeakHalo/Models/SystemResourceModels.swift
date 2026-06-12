import AppKit
import Foundation

struct CPUUsageBreakdown: Equatable {
    let total: Double
    let user: Double
    let system: Double
    let nice: Double
    let idle: Double
}

struct CPUTicks: Equatable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

struct GPUMetrics: Equatable {
    let usage: Double?
    let renderUsage: Double?
    let tilerUsage: Double?
    let usedMemoryBytes: UInt64?
    let allocatedMemoryBytes: UInt64?
    let deviceName: String?

    static let unavailable = GPUMetrics(
        usage: nil,
        renderUsage: nil,
        tilerUsage: nil,
        usedMemoryBytes: nil,
        allocatedMemoryBytes: nil,
        deviceName: nil
    )
}

struct MemoryStats: Equatable {
    let usedBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let swapUsedBytes: UInt64
    let totalBytes: UInt64

    var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100))
    }
}

struct MemoryPageCounts: Equatable {
    let internalPages: UInt64
    let purgeablePages: UInt64
    let wiredPages: UInt64
    let compressedPages: UInt64
    let externalPages: UInt64
    let speculativePages: UInt64
}

struct NetworkStats: Equatable {
    let downloadBytesPerSecond: UInt64?
    let uploadBytesPerSecond: UInt64?
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

struct NetworkCounters: Equatable {
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let timestamp: Date
}

struct StorageStats: Equatable {
    let usedBytes: UInt64
    let freeBytes: UInt64
    let totalBytes: UInt64
    let externalVolumes: [StorageVolumeStats]

    var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100))
    }
}

struct StorageVolumeStats: Equatable, Identifiable {
    let id: String
    let name: String
    let usedBytes: UInt64
    let freeBytes: UInt64
    let totalBytes: UInt64

    var usagePercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100))
    }
}

struct BatteryStats: Equatable {
    let level: Double?
    let isCharging: Bool?
    let isPluggedIn: Bool?
    let cycleCount: Int?
    let health: String?
    let temperatureCelsius: Double?
    let powerWatts: Double?

    var isAvailable: Bool {
        level != nil
            || isCharging != nil
            || isPluggedIn != nil
            || cycleCount != nil
            || health != nil
            || temperatureCelsius != nil
            || powerWatts != nil
    }
}

enum HardwareSensorSource: String, Equatable {
    case helper
    case app
    case unavailable

    var title: String {
        switch self {
        case .helper:
            "Helper"
        case .app:
            "App"
        case .unavailable:
            "Unavailable"
        }
    }
}

struct HardwareSensors: Equatable {
    let cpuTemperatureCelsius: Double?
    let fanSpeedRPM: Double?
    let source: HardwareSensorSource
    let message: String?
    let updatedAt: Date?

    static let unavailable = HardwareSensors(
        cpuTemperatureCelsius: nil,
        fanSpeedRPM: nil,
        source: .unavailable,
        message: nil,
        updatedAt: nil
    )
}

struct SystemResourceStats: Equatable {
    var cpu: CPUUsageBreakdown?
    var gpu: GPUMetrics
    var memory: MemoryStats
    var network: NetworkStats
    var storage: StorageStats?
    var battery: BatteryStats?
    var sensors: HardwareSensors
    var timestamp: Date

    static let empty = SystemResourceStats(
        cpu: nil,
        gpu: .unavailable,
        memory: MemoryStats(
            usedBytes: 0,
            appBytes: 0,
            wiredBytes: 0,
            compressedBytes: 0,
            cachedBytes: 0,
            swapUsedBytes: 0,
            totalBytes: ProcessInfo.processInfo.physicalMemory
        ),
        network: NetworkStats(
            downloadBytesPerSecond: nil,
            uploadBytesPerSecond: nil,
            receivedBytes: 0,
            sentBytes: 0
        ),
        storage: nil,
        battery: nil,
        sensors: .unavailable,
        timestamp: .distantPast
    )
}

struct ProcessResourceItem: Identifiable {
    let id: String
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let processCount: Int
    let cpuUsage: Double
    let cumulativeCPUTimeSeconds: TimeInterval
    let memoryBytes: UInt64
    let peakMemoryBytes: UInt64
    let icon: NSImage?
    let application: NSRunningApplication?

    var detailText: String {
        processCount > 1 ? "\(processCount) processes" : "PID \(pid)"
    }

    var canTerminate: Bool {
        application != nil && !ProcessProtection.isProtected(name: name, bundleIdentifier: bundleIdentifier)
    }
}

struct AppKillResult: Equatable {
    let success: Bool
    let message: String
}
