import Foundation
import IOKit
import IOKit.ps

final class BatteryUsageSampler {
    func sample() -> BatteryStats? {
        let sourceStats = readPowerSourceStats()
        let registryStats = readRegistryStats()
        let merged = BatteryStats(
            level: sourceStats.level ?? registryStats.level,
            isCharging: sourceStats.isCharging ?? registryStats.isCharging,
            isPluggedIn: sourceStats.isPluggedIn ?? registryStats.isPluggedIn,
            cycleCount: registryStats.cycleCount,
            health: registryStats.health,
            temperatureCelsius: registryStats.temperatureCelsius,
            powerWatts: registryStats.powerWatts
        )
        return merged.isAvailable ? merged : nil
    }

    static func statsFromPowerSource(_ description: [String: Any]) -> BatteryStats {
        let current = doubleValue(description[kIOPSCurrentCapacityKey])
        let max = doubleValue(description[kIOPSMaxCapacityKey])
        let level = batteryLevel(currentCapacity: current, maxCapacity: max)
        let state = description[kIOPSPowerSourceStateKey] as? String
        let isCharging = description[kIOPSIsChargingKey] as? Bool
        let isPluggedIn = state == kIOPSACPowerValue

        return BatteryStats(
            level: level,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            cycleCount: nil,
            health: nil,
            temperatureCelsius: nil,
            powerWatts: nil
        )
    }

    static func batteryLevel(currentCapacity: Double?, maxCapacity: Double?) -> Double? {
        guard let currentCapacity, let maxCapacity, maxCapacity > 0 else { return nil }
        return min(100, max(0, currentCapacity / maxCapacity * 100))
    }

    static func temperatureCelsius(fromDeciKelvin value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value / 10 - 273.15
    }

    private func readPowerSourceStats() -> BatteryStats {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return empty
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else {
                continue
            }
            return Self.statsFromPowerSource(description)
        }

        return empty
    }

    private func readRegistryStats() -> BatteryStats {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != IO_OBJECT_NULL else { return empty }
        defer { IOObjectRelease(service) }

        let cycleCount = property(service, "CycleCount") as? Int
        let health = property(service, "BatteryHealth") as? String
        let temperature = Self.temperatureCelsius(
            fromDeciKelvin: Self.doubleValue(property(service, "Temperature"))
        )
        let voltage = Self.doubleValue(property(service, "Voltage")).map { $0 / 1000 }
        let amperage = Self.doubleValue(property(service, "Amperage")).map { $0 / 1000 }
        let powerWatts = voltage.flatMap { voltage in
            amperage.map { abs(voltage * $0) }
        }
        let current = Self.doubleValue(property(service, "CurrentCapacity"))
        let max = Self.doubleValue(property(service, "MaxCapacity"))
        let isCharging = property(service, "IsCharging") as? Bool
        let externalConnected = property(service, "ExternalConnected") as? Bool

        return BatteryStats(
            level: Self.batteryLevel(currentCapacity: current, maxCapacity: max),
            isCharging: isCharging,
            isPluggedIn: externalConnected,
            cycleCount: cycleCount,
            health: health,
            temperatureCelsius: temperature,
            powerWatts: powerWatts
        )
    }

    private func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
    }

    private var empty: BatteryStats {
        BatteryStats(
            level: nil,
            isCharging: nil,
            isPluggedIn: nil,
            cycleCount: nil,
            health: nil,
            temperatureCelsius: nil,
            powerWatts: nil
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
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
}
