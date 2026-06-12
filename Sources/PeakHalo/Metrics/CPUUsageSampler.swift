import Darwin
import Foundation

final class CPUUsageSampler {
    private var previousTicks: CPUTicks?

    func sample() -> CPUUsageBreakdown? {
        guard let currentTicks = Self.readTicks() else { return nil }
        defer { previousTicks = currentTicks }
        return Self.calculate(previous: previousTicks, current: currentTicks)
    }

    static func calculate(previous: CPUTicks?, current: CPUTicks) -> CPUUsageBreakdown? {
        guard let previous else { return nil }
        guard current.user >= previous.user,
              current.system >= previous.system,
              current.idle >= previous.idle,
              current.nice >= previous.nice else {
            return nil
        }

        let user = current.user - previous.user
        let system = current.system - previous.system
        let idle = current.idle - previous.idle
        let nice = current.nice - previous.nice
        let totalTicks = user + system + idle + nice

        guard totalTicks > 0 else { return nil }

        let denominator = Double(totalTicks)
        let userPercent = Double(user) / denominator * 100
        let systemPercent = Double(system) / denominator * 100
        let nicePercent = Double(nice) / denominator * 100
        let idlePercent = Double(idle) / denominator * 100

        return CPUUsageBreakdown(
            total: min(100, max(0, userPercent + systemPercent + nicePercent)),
            user: min(100, max(0, userPercent)),
            system: min(100, max(0, systemPercent)),
            nice: min(100, max(0, nicePercent)),
            idle: min(100, max(0, idlePercent))
        )
    }

    private static func readTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }

        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }
}
