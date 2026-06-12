import Foundation
import IOKit
import IOKit.ps
import IOBluetooth
import ObjectiveC.runtime

final class BatteryDeviceService {
    private let computerSampler = BatteryUsageSampler()

    func devices() -> [BatteryDevice] {
        let now = Date()
        var collected: [BatteryDevice] = []

        if let computer = computerDevice(updatedAt: now) {
            collected.append(computer)
        }

        collected.append(contentsOf: powerSourceDevices(updatedAt: now))
        collected.append(contentsOf: registryDevices(updatedAt: now))
        collected.append(contentsOf: iobluetoothDevices(updatedAt: now))
        collected.append(contentsOf: bluetoothDevices(updatedAt: now))

        return mergedDevices(collected)
    }

    private func computerDevice(updatedAt: Date) -> BatteryDevice? {
        guard let stats = computerSampler.sample(), stats.isAvailable else { return nil }

        return BatteryDevice(
            id: "battery.computer.internal",
            name: String(localized: "Computer"),
            kind: .computer,
            level: stats.level,
            isCharging: stats.isCharging,
            isConnected: true,
            detail: computerDetail(for: stats),
            source: "IOPowerSources",
            updatedAt: updatedAt
        )
    }

    private func powerSourceDevices(updatedAt: Date) -> [BatteryDevice] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return []
        }

        return sources.compactMap { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else {
                return nil
            }

            if (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType {
                return nil
            }

            let stats = BatteryUsageSampler.statsFromPowerSource(description)
            let name = stringValue(description[kIOPSNameKey])
                ?? stringValue(description["Name"])
                ?? String(localized: "Unknown Battery")
            let kind = inferKind(name: name, properties: description)

            guard stats.isAvailable || kind != .unknown else { return nil }

            return BatteryDevice(
                id: "battery.powersource.\(stableToken(from: name))",
                name: name,
                kind: kind,
                level: stats.level,
                isCharging: stats.isCharging,
                isConnected: true,
                detail: detail(from: description, fallback: stats.isCharging == true ? String(localized: "Charging") : nil),
                source: "IOPowerSources",
                updatedAt: updatedAt
            )
        }
    }

    private func registryDevices(updatedAt: Date) -> [BatteryDevice] {
        let classes = [
            "AppleDeviceManagementHIDEventService",
            "AppleUserHIDEventService",
            "IOHIDEventService",
            "IOBluetoothHIDDriver",
            "AppleHSBluetoothDevice",
            "BNBMouseDevice",
            "BNBTrackpadDevice",
            "AppleBluetoothHIDKeyboard",
            "AppleBluetoothHIDMouse"
        ]

        return classes.flatMap { registryDevices(className: $0, updatedAt: updatedAt) }
    }

    private func iobluetoothDevices(updatedAt: Date) -> [BatteryDevice] {
        let devices = (IOBluetoothDevice.pairedDevices() ?? [])
            .compactMap { $0 as? IOBluetoothDevice }
            .filter { $0.isConnected() }

        return devices.compactMap { device in
            let name = device.nameOrAddress ?? device.addressString ?? String(localized: "Unknown Battery")
            let properties: [String: Any] = [
                "Product": name,
                "Transport": "Bluetooth"
            ]
            let kind = inferKind(name: name, properties: properties)
            guard kind != .unknown else { return nil }

            let levels = iobluetoothBatteryLevels(for: device)
            let level = levels["Main"] ?? levels.values.first
            guard level != nil || kind == .headphones else { return nil }

            let address = device.addressString ?? name
            return BatteryDevice(
                id: "battery.iobluetooth.\(stableToken(from: address))",
                name: name,
                kind: kind,
                level: level,
                isCharging: nil,
                isConnected: true,
                detail: bluetoothDetail(from: properties, levels: levels),
                source: "IOBluetooth",
                updatedAt: updatedAt
            )
        }
    }

    private func iobluetoothBatteryLevels(for device: IOBluetoothDevice) -> [String: Double] {
        let object = device as NSObject
        let readings: [(String, String)] = [
            ("batteryPercentSingle", "Main"),
            ("batteryPercentCombined", "Main"),
            ("batteryPercentLeft", "Left"),
            ("batteryPercentRight", "Right"),
            ("batteryPercentCase", "Case")
        ]

        var levels: [String: Double] = [:]
        for (selector, key) in readings {
            guard let value = unsignedByteValue(object, selector), value > 0, value <= 100 else {
                continue
            }

            levels[key] = Double(value)
        }

        if levels.isEmpty,
           let headsetBattery = integerValue(object, "headsetBattery"),
           headsetBattery > 0 {
            levels["Main"] = headsetBattery <= 5
                ? min(100, max(0, Double(headsetBattery) / 5 * 100))
                : min(100, max(0, Double(headsetBattery)))
        }

        return levels
    }

    private func bluetoothDevices(updatedAt: Date) -> [BatteryDevice] {
        guard let json = systemProfilerBluetoothJSON(),
              let groups = json["SPBluetoothDataType"] as? [[String: Any]] else {
            return []
        }

        return groups.flatMap { group in
            guard let connected = group["device_connected"] as? [[String: Any]] else {
                return [BatteryDevice]()
            }

            return connected.compactMap { entry -> BatteryDevice? in
                guard let name = entry.keys.first,
                      let properties = entry[name] as? [String: Any] else {
                    return nil
                }

                let kind = inferKind(name: name, properties: properties)
                guard kind != .unknown else { return nil }

                let levels = bluetoothBatteryLevels(from: properties)
                let level = levels["Main"] ?? levels.values.first
                let address = stringValue(properties["device_address"])
                let sourceID = address ?? name

                return BatteryDevice(
                    id: "battery.bluetooth.\(stableToken(from: sourceID))",
                    name: name,
                    kind: kind,
                    level: level,
                    isCharging: nil,
                    isConnected: true,
                    detail: bluetoothDetail(from: properties, levels: levels),
                    source: "SystemProfilerBluetooth",
                    updatedAt: updatedAt
                )
            }
        }
    }

    private func systemProfilerBluetoothJSON() -> [String: Any]? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func bluetoothBatteryLevels(from properties: [String: Any]) -> [String: Double] {
        let keys: [(String, String)] = [
            ("device_batteryLevelMain", "Main"),
            ("device_batteryLevelLeft", "Left"),
            ("device_batteryLevelRight", "Right"),
            ("device_batteryLevelCase", "Case")
        ]

        return keys.reduce(into: [:]) { result, pair in
            guard let value = properties[pair.0],
                  let percent = percentValue(value) else {
                return
            }

            result[pair.1] = percent
        }
    }

    private func bluetoothDetail(from properties: [String: Any], levels: [String: Double]) -> String? {
        if levels.count > 1 {
            return levels
                .sorted { $0.key < $1.key }
                .map { "\(bluetoothBatteryPartTitle($0.key)) \(Int($0.value.rounded()))%" }
                .joined(separator: " · ")
        }

        return String(localized: "Bluetooth")
    }

    private func bluetoothBatteryPartTitle(_ key: String) -> String {
        switch key {
        case "Left":
            String(localized: "Left")
        case "Right":
            String(localized: "Right")
        case "Case":
            String(localized: "Case")
        case "Main":
            String(localized: "Main")
        default:
            key
        }
    }

    private func registryDevices(className: String, updatedAt: Date) -> [BatteryDevice] {
        guard let matching = IOServiceMatching(className) else { return [] }

        var iterator: io_iterator_t = IO_OBJECT_NULL
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [BatteryDevice] = []
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            if let device = registryDevice(service: service, className: className, updatedAt: updatedAt) {
                devices.append(device)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return devices
    }

    private func registryDevice(service: io_service_t, className: String, updatedAt: Date) -> BatteryDevice? {
        guard let properties = properties(for: service) else { return nil }
        let name = deviceName(from: properties, service: service)
        let kind = inferKind(name: name, properties: properties)
        let level = batteryLevel(from: properties)
        let isCharging = boolValue(
            properties["IsCharging"]
                ?? properties["BatteryIsCharging"]
                ?? properties["Charging"]
        )

        guard level != nil || isCharging != nil || likelyBatteryPeripheral(kind: kind, properties: properties) else {
            return nil
        }

        return BatteryDevice(
            id: "battery.registry.\(stableID(name: name, className: className, properties: properties))",
            name: name,
            kind: kind,
            level: level,
            isCharging: isCharging,
            isConnected: true,
            detail: detail(from: properties, fallback: level == nil ? String(localized: "Battery unavailable") : nil),
            source: className,
            updatedAt: updatedAt
        )
    }

    private func properties(for service: io_service_t) -> [String: Any]? {
        var rawProperties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &rawProperties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = rawProperties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return properties
    }

    private func deviceName(from properties: [String: Any], service: io_service_t) -> String {
        let keys = [
            "Product",
            "ProductName",
            "Product Name",
            "DeviceName",
            "Device Name",
            "Name",
            "IORegistryEntryName",
            "Bluetooth Product Name"
        ]

        for key in keys {
            if let name = stringValue(properties[key]), !name.isEmpty {
                return name
            }
        }

        if let registryName = registryEntryName(service), !registryName.isEmpty {
            return registryName
        }

        return String(localized: "Unknown Battery")
    }

    private func registryEntryName(_ service: io_service_t) -> String? {
        var name = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
        let result = name.withUnsafeMutableBufferPointer { buffer in
            IORegistryEntryGetName(service, buffer.baseAddress)
        }

        guard result == KERN_SUCCESS else { return nil }
        return String(cString: name)
    }

    private func batteryLevel(from properties: [String: Any]) -> Double? {
        let keys = [
            "BatteryPercent",
            "BatteryPercentage",
            "Battery Percentage",
            "DeviceBatteryPercent",
            "BatteryLevel",
            "Battery Level",
            "Battery",
            "CurrentBatteryPercent"
        ]

        for key in keys {
            guard let value = properties[key] else { continue }
            if let percent = percentValue(value) {
                return percent
            }
        }

        let current = doubleValue(properties["CurrentCapacity"] ?? properties["Current Capacity"])
        let maximum = doubleValue(properties["MaxCapacity"] ?? properties["Max Capacity"])
        return BatteryUsageSampler.batteryLevel(currentCapacity: current, maxCapacity: maximum)
    }

    private func percentValue(_ value: Any) -> Double? {
        if let numeric = doubleValue(value) {
            if numeric.isNaN || numeric.isInfinite || numeric < 0 {
                return nil
            }

            if numeric <= 1 {
                return min(100, max(0, numeric * 100))
            }

            if numeric <= 100 {
                return numeric
            }

            if numeric <= 255 {
                return min(100, max(0, numeric / 255 * 100))
            }
        }

        if let string = stringValue(value) {
            let filtered = string.filter { $0.isNumber || $0 == "." }
            return Double(filtered).map { min(100, max(0, $0)) }
        }

        return nil
    }

    private func inferKind(name: String, properties: [String: Any]) -> BatteryDeviceKind {
        let value = [
            name,
            stringValue(properties["Product"]),
            stringValue(properties["ProductName"]),
            stringValue(properties["Transport"]),
            stringValue(properties["device_minorType"])
        ]
        .compactMap { $0 }
        .joined(separator: " ")
            .lowercased()

        if value.contains("airpods")
            || value.contains("headphone")
            || value.contains("headset")
            || value.contains("earbud")
            || value.contains("freeclip")
            || value.contains("buds")
            || value.contains("耳机") {
            return .headphones
        }

        if value.contains("trackpad") || value.contains("触控板") {
            return .trackpad
        }

        if value.contains("keyboard") || value.contains("键盘") {
            return .keyboard
        }

        if value.contains("mouse") || value.contains("鼠标") {
            return .mouse
        }

        if value.contains("macbook") || value.contains("built-in") || value.contains("internal") {
            return .computer
        }

        return .unknown
    }

    private func likelyBatteryPeripheral(kind: BatteryDeviceKind, properties: [String: Any]) -> Bool {
        guard kind != .computer, kind != .unknown else { return false }

        if properties.keys.contains(where: { $0.localizedCaseInsensitiveContains("battery") }) {
            return true
        }

        let transport = stringValue(properties["Transport"])?.lowercased()
        return transport?.contains("bluetooth") == true
    }

    private func detail(from properties: [String: Any], fallback: String?) -> String? {
        if boolValue(properties["LowBattery"] ?? properties["Low Battery"]) == true {
            return String(localized: "Low Battery")
        }

        if let transport = stringValue(properties["Transport"]), !transport.isEmpty {
            return transport
        }

        if let state = stringValue(properties[kIOPSPowerSourceStateKey]), !state.isEmpty {
            if state == kIOPSACPowerValue {
                return String(localized: "Plugged In")
            }
            if state == kIOPSBatteryPowerValue {
                return String(localized: "On Battery")
            }
            return state
        }

        return fallback
    }

    private func computerDetail(for stats: BatteryStats) -> String? {
        if stats.isCharging == true {
            return String(localized: "Charging")
        }

        if stats.isPluggedIn == true {
            return String(localized: "Plugged In")
        }

        if stats.isPluggedIn == false {
            return String(localized: "On Battery")
        }

        return nil
    }

    private func mergedDevices(_ devices: [BatteryDevice]) -> [BatteryDevice] {
        var merged: [String: BatteryDevice] = [:]

        for device in devices {
            let key = mergeKey(for: device)
            if let existing = merged[key] {
                merged[key] = preferredDevice(existing, device)
            } else {
                merged[key] = device
            }
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.kind.sortRank != rhs.kind.sortRank {
                return lhs.kind.sortRank < rhs.kind.sortRank
            }

            if lhs.hasBatteryReading != rhs.hasBatteryReading {
                return lhs.hasBatteryReading
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func preferredDevice(_ lhs: BatteryDevice, _ rhs: BatteryDevice) -> BatteryDevice {
        if lhs.hasBatteryReading != rhs.hasBatteryReading {
            return lhs.hasBatteryReading ? lhs : rhs
        }

        if lhs.level == nil, rhs.level != nil {
            return rhs
        }

        if lhs.detail == nil, rhs.detail != nil {
            return rhs
        }

        return lhs
    }

    private func mergeKey(for device: BatteryDevice) -> String {
        if device.kind == .computer {
            return "computer"
        }

        return "\(device.kind.rawValue).\(stableToken(from: device.name))"
    }

    private func stableID(name: String, className: String, properties: [String: Any]) -> String {
        let keys = [
            "SerialNumber",
            "Serial Number",
            "DeviceAddress",
            "Device Address",
            "BluetoothAddress",
            "BD_ADDR",
            "LocationID"
        ]

        for key in keys {
            if let value = stringValue(properties[key]), !value.isEmpty {
                return stableToken(from: "\(className).\(value)")
            }
        }

        let vendor = stringValue(properties["VendorID"] ?? properties["Vendor ID"])
        let product = stringValue(properties["ProductID"] ?? properties["Product ID"])
        if let vendor, let product {
            return stableToken(from: "\(className).\(vendor).\(product).\(name)")
        }

        return stableToken(from: "\(className).\(name)")
    }

    private func stableToken(from value: String) -> String {
        let scalars = value.lowercased().unicodeScalars
        var token = ""

        for scalar in scalars {
            token.append(CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "-")
        }

        while token.contains("--") {
            token = token.replacingOccurrences(of: "--", with: "-")
        }

        return token.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        case let value as Data:
            return String(data: value, encoding: .utf8)
        default:
            return nil
        }
    }

    private func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            let lowercased = value.lowercased()
            if ["true", "yes", "1"].contains(lowercased) {
                return true
            }
            if ["false", "no", "0"].contains(lowercased) {
                return false
            }
            return nil
        default:
            return nil
        }
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
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private func unsignedByteValue(_ object: NSObject, _ selectorName: String) -> UInt8? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let method = class_getInstanceMethod(type(of: object), selector) else {
            return nil
        }

        let implementation = method_getImplementation(method)
        typealias Function = @convention(c) (AnyObject, Selector) -> UInt8
        return unsafeBitCast(implementation, to: Function.self)(object, selector)
    }

    private func integerValue(_ object: NSObject, _ selectorName: String) -> Int64? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector),
              let method = class_getInstanceMethod(type(of: object), selector) else {
            return nil
        }

        let implementation = method_getImplementation(method)
        typealias Function = @convention(c) (AnyObject, Selector) -> Int64
        return unsafeBitCast(implementation, to: Function.self)(object, selector)
    }
}
