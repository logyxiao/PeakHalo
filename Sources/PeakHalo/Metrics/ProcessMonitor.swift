import AppKit
import Darwin
import Foundation

final class ProcessMonitor {
    private var previousSamples: [pid_t: ProcessSample] = [:]
    private var previousAggregatePeakMemory: [String: UInt64] = [:]
    private var bundleMetadataCache: [String: ProcessBundleMetadata] = [:]
    private var appIconCache: [String: NSImage] = [:]

    func sample() -> [ProcessResourceItem] {
        let now = Date()
        let observations = readProcessObservations()
        let result = Self.aggregate(
            observations: observations,
            previousSamples: previousSamples,
            previousAggregatePeakMemory: previousAggregatePeakMemory,
            timestamp: now
        )

        previousSamples = result.processSamples
        previousAggregatePeakMemory = result.aggregatePeakMemory
        return result.items
    }

    static func aggregate(
        observations: [ProcessObservation],
        previousSamples: [pid_t: ProcessSample],
        previousAggregatePeakMemory: [String: UInt64],
        timestamp: Date
    ) -> ProcessAggregationResult {
        var nextSamples: [pid_t: ProcessSample] = [:]
        var builders: [String: ProcessAggregateBuilder] = [:]

        for observation in observations {
            let key = aggregationKey(for: observation)
            let displayName = observation.appName ?? observation.processName
            let bundleIdentifier = observation.appBundleIdentifier
            let previousSample = previousSamples[observation.pid]
            let cpuDeltaSeconds = cpuTimeDelta(previous: previousSample, totalCPUTime: observation.totalCPUTime)
            let cpuUsage = processCPUUsage(previous: previousSample, cpuDeltaSeconds: cpuDeltaSeconds, now: timestamp)
            let cumulativeCPUTimeSeconds = (previousSample?.cumulativeCPUTimeSeconds ?? 0) + cpuDeltaSeconds

            nextSamples[observation.pid] = ProcessSample(
                totalCPUTime: observation.totalCPUTime,
                timestamp: timestamp,
                cumulativeCPUTimeSeconds: cumulativeCPUTimeSeconds
            )

            var builder = builders[key] ?? ProcessAggregateBuilder(
                id: key,
                representativePID: observation.pid,
                name: displayName,
                bundleIdentifier: bundleIdentifier,
                icon: observation.icon,
                application: observation.application
            )
            builder.add(
                observation: observation,
                cpuUsage: cpuUsage,
                cumulativeCPUTimeSeconds: cumulativeCPUTimeSeconds
            )
            builders[key] = builder
        }

        var aggregatePeakMemory = previousAggregatePeakMemory
        let items = builders.values.map { builder -> ProcessResourceItem in
            let peakMemory = max(aggregatePeakMemory[builder.id] ?? 0, builder.memoryBytes)
            aggregatePeakMemory[builder.id] = peakMemory

            return ProcessResourceItem(
                id: builder.id,
                pid: builder.representativePID,
                name: builder.name,
                bundleIdentifier: builder.bundleIdentifier,
                processCount: builder.processCount,
                cpuUsage: builder.cpuUsage,
                cumulativeCPUTimeSeconds: builder.cumulativeCPUTimeSeconds,
                memoryBytes: builder.memoryBytes,
                peakMemoryBytes: peakMemory,
                icon: builder.icon,
                application: builder.application
            )
        }

        return ProcessAggregationResult(
            items: items,
            processSamples: nextSamples,
            aggregatePeakMemory: aggregatePeakMemory
        )
    }

    static func processCPUUsage(
        previous: ProcessSample?,
        cpuDeltaSeconds: TimeInterval,
        now: Date
    ) -> Double {
        guard let previous else { return 0 }
        let interval = now.timeIntervalSince(previous.timestamp)
        guard interval > 0 else { return 0 }
        return max(0, cpuDeltaSeconds / interval * 100)
    }

    static func cpuTimeDelta(previous: ProcessSample?, totalCPUTime: UInt64) -> TimeInterval {
        guard let previous, totalCPUTime >= previous.totalCPUTime else { return 0 }
        return Double(totalCPUTime - previous.totalCPUTime) / 1_000_000_000
    }

    static func appBundlePath(from processPath: String) -> String? {
        if let range = processPath.range(of: ".app/", options: .caseInsensitive) {
            let endIndex = processPath.index(range.lowerBound, offsetBy: 4)
            return String(processPath[..<endIndex])
        }

        if processPath.lowercased().hasSuffix(".app") {
            return processPath
        }

        return nil
    }

    private func readProcessObservations() -> [ProcessObservation] {
        let contexts = runningApplicationContexts()
        let currentUserID = getuid()

        return listProcessIDs().compactMap { pid -> ProcessObservation? in
            guard let bsdInfo = readBSDInfo(pid: pid), bsdInfo.pbi_uid == currentUserID else {
                return nil
            }

            guard let taskInfo = readTaskInfo(pid: pid) else { return nil }

            let processName = Self.string(from: bsdInfo.pbi_name)
            let processPath = readProcessPath(pid: pid)
            let appBundlePath = processPath.flatMap(Self.appBundlePath(from:))
                ?? contexts.byPID[pid]?.bundlePath
            let appContext = contexts.byPID[pid]
                ?? appBundlePath.flatMap { contexts.byPath[$0] }
            let bundleMetadata = appBundlePath.map { metadata(forBundlePath: $0) }
            let appName = appContext?.name
                ?? bundleMetadata?.displayName
                ?? appBundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            let bundleIdentifier = appContext?.bundleIdentifier ?? bundleMetadata?.bundleIdentifier
            let memoryBytes = readPhysicalFootprint(pid: pid) ?? UInt64(taskInfo.pti_resident_size)

            return ProcessObservation(
                pid: pid,
                userID: bsdInfo.pbi_uid,
                processName: processName.isEmpty ? "PID \(pid)" : processName,
                processPath: processPath,
                appName: appName,
                appBundleIdentifier: bundleIdentifier,
                appBundlePath: appBundlePath,
                totalCPUTime: taskInfo.pti_total_user + taskInfo.pti_total_system,
                memoryBytes: memoryBytes,
                icon: appContext?.icon,
                application: appContext?.application
            )
        }
    }

    private func listProcessIDs() -> [pid_t] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        let capacity = Int(byteCount) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)
        let actualByteCount = pids.withUnsafeMutableBufferPointer {
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                $0.baseAddress,
                Int32($0.count * MemoryLayout<pid_t>.stride)
            )
        }

        guard actualByteCount > 0 else { return [] }
        let count = min(Int(actualByteCount) / MemoryLayout<pid_t>.stride, pids.count)
        return pids.prefix(count).filter { $0 > 0 }
    }

    private func readBSDInfo(pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: UInt8.self, capacity: size) {
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(size))
            }
        }

        guard result == Int32(size) else { return nil }
        return info
    }

    private func readTaskInfo(pid: pid_t) -> proc_taskinfo? {
        var taskInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: UInt8.self, capacity: size) {
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(size))
            }
        }

        guard result == Int32(size) else { return nil }
        return taskInfo
    }

    private func readProcessPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = buffer.withUnsafeMutableBufferPointer {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }

        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    private func metadata(forBundlePath path: String) -> ProcessBundleMetadata {
        if let cached = bundleMetadataCache[path] {
            return cached
        }

        let bundle = Bundle(url: URL(fileURLWithPath: path))
        let metadata = ProcessBundleMetadata(
            displayName: Self.bundleDisplayName(from: bundle),
            bundleIdentifier: bundle?.bundleIdentifier
        )
        bundleMetadataCache[path] = metadata
        trimCacheIfNeeded(&bundleMetadataCache)
        return metadata
    }

    private func readPhysicalFootprint(pid: pid_t) -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }

        guard result == 0, usage.ri_phys_footprint > 0 else { return nil }
        return usage.ri_phys_footprint
    }

    private func runningApplicationContexts() -> RunningApplicationContexts {
        var byPID: [pid_t: RunningApplicationContext] = [:]
        var byPath: [String: RunningApplicationContext] = [:]

        for application in NSWorkspace.shared.runningApplications where !application.isTerminated {
            let bundlePath = application.bundleURL?.path
            let context = RunningApplicationContext(
                name: application.localizedName
                    ?? bundlePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent },
                bundleIdentifier: application.bundleIdentifier,
                bundlePath: bundlePath,
                icon: icon(for: application, bundlePath: bundlePath),
                application: application
            )

            byPID[application.processIdentifier] = context
            if let bundlePath, byPath[bundlePath] == nil {
                byPath[bundlePath] = context
            }
        }

        return RunningApplicationContexts(byPID: byPID, byPath: byPath)
    }

    private func icon(for application: NSRunningApplication, bundlePath: String?) -> NSImage? {
        let key = application.bundleIdentifier
            ?? bundlePath
            ?? "pid:\(application.processIdentifier)"

        if let cached = appIconCache[key] {
            return cached
        }

        let icon = application.icon
        appIconCache[key] = icon
        trimCacheIfNeeded(&appIconCache)
        return icon
    }

    private func trimCacheIfNeeded<Value>(_ cache: inout [String: Value]) {
        guard cache.count > 160 else { return }
        cache.removeAll(keepingCapacity: true)
    }

    private static func aggregationKey(for observation: ProcessObservation) -> String {
        if let appBundlePath = observation.appBundlePath {
            return "app:\(appBundlePath)"
        }

        return "pid:\(observation.pid)"
    }

    private static func bundleDisplayName(from bundle: Bundle?) -> String? {
        guard let bundle else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
    }

    private static func string<T>(from tuple: T) -> String {
        var copy = tuple
        return withUnsafeBytes(of: &copy) { buffer in
            let bytes = Array(buffer.prefix { $0 != 0 })
            return String(bytes: bytes, encoding: .utf8) ?? ""
        }
    }
}

private struct ProcessBundleMetadata {
    let displayName: String?
    let bundleIdentifier: String?
}

struct ProcessObservation {
    let pid: pid_t
    let userID: uid_t
    let processName: String
    let processPath: String?
    let appName: String?
    let appBundleIdentifier: String?
    let appBundlePath: String?
    let totalCPUTime: UInt64
    let memoryBytes: UInt64
    let icon: NSImage?
    let application: NSRunningApplication?
}

struct ProcessSample {
    let totalCPUTime: UInt64
    let timestamp: Date
    let cumulativeCPUTimeSeconds: TimeInterval
}

struct ProcessAggregationResult {
    let items: [ProcessResourceItem]
    let processSamples: [pid_t: ProcessSample]
    let aggregatePeakMemory: [String: UInt64]
}

private struct ProcessAggregateBuilder {
    let id: String
    let representativePID: pid_t
    let name: String
    let bundleIdentifier: String?
    var icon: NSImage?
    var application: NSRunningApplication?
    var processCount = 0
    var cpuUsage: Double = 0
    var cumulativeCPUTimeSeconds: TimeInterval = 0
    var memoryBytes: UInt64 = 0

    mutating func add(
        observation: ProcessObservation,
        cpuUsage: Double,
        cumulativeCPUTimeSeconds: TimeInterval
    ) {
        processCount += 1
        self.cpuUsage += cpuUsage
        self.cumulativeCPUTimeSeconds += cumulativeCPUTimeSeconds
        memoryBytes += observation.memoryBytes
        icon = icon ?? observation.icon
        application = application ?? observation.application
    }
}

private struct RunningApplicationContext {
    let name: String?
    let bundleIdentifier: String?
    let bundlePath: String?
    let icon: NSImage?
    let application: NSRunningApplication
}

private struct RunningApplicationContexts {
    let byPID: [pid_t: RunningApplicationContext]
    let byPath: [String: RunningApplicationContext]
}
