import Foundation
import IOKit
import IOKit.graphics

final class GPUMetricsCollector {
    func collect() -> GPUMetrics {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return .unavailable
        }
        defer { IOObjectRelease(iterator) }

        var readings: [GPUMetrics] = []
        var service = IOIteratorNext(iterator)

        while service != 0 {
            if let properties = copyProperties(for: service) {
                let stats = properties["PerformanceStatistics"] as? [String: Any] ?? [:]
                let usage = percentValue(
                    stats["Device Utilization %"]
                        ?? stats["GPU Activity(%)"]
                )
                let reading = GPUMetrics(
                    usage: usage,
                    renderUsage: percentValue(stats["Renderer Utilization %"]),
                    tilerUsage: percentValue(stats["Tiler Utilization %"]),
                    usedMemoryBytes: byteValue(stats["In use system memory"]),
                    allocatedMemoryBytes: byteValue(stats["Alloc system memory"]),
                    deviceName: deviceName(from: properties)
                        ?? stringValue(properties["IOClass"])
                )
                if reading.usage != nil
                    || reading.renderUsage != nil
                    || reading.tilerUsage != nil
                    || reading.usedMemoryBytes != nil {
                    readings.append(reading)
                }
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return readings.max { ($0.usage ?? 0) < ($1.usage ?? 0) } ?? .unavailable
    }

    private func copyProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)

        guard result == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return dictionary
    }

    private func deviceName(from properties: [String: Any]) -> String? {
        let stats = properties["PerformanceStatistics"] as? [String: Any] ?? [:]
        let raw = stringValue(stats["model"]) ?? stringValue(properties["model"])
        return raw?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func percentValue(_ value: Any?) -> Double? {
        guard let number = doubleValue(value), number.isFinite else { return nil }
        return min(100, max(0, number))
    }

    private func byteValue(_ value: Any?) -> UInt64? {
        guard let number = doubleValue(value), number.isFinite, number >= 0 else { return nil }
        return UInt64(number.rounded())
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as Int:
            return Double(value)
        case let value as Int64:
            return Double(value)
        case let value as UInt64:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        default:
            return nil
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }

        if let data = value as? Data {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }
}
