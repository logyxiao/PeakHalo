import CoreGraphics
import Darwin
import Foundation
import IOKit

enum DisplayControlKind: Hashable, CaseIterable {
    case brightness
    case volume

    var title: String {
        switch self {
        case .brightness:
            String(localized: "Brightness")
        case .volume:
            String(localized: "Volume")
        }
    }

    var systemImage: String {
        switch self {
        case .brightness:
            "sun.max"
        case .volume:
            "speaker.wave.2"
        }
    }

    var defaultValue: Double {
        switch self {
        case .brightness:
            50
        case .volume:
            40
        }
    }

    var storageKey: String {
        switch self {
        case .brightness:
            "brightness"
        case .volume:
            "volume"
        }
    }
}

struct ControlledDisplay: Equatable, Identifiable {
    let id: CGDirectDisplayID
    let storageID: String
    let name: String
    let isBuiltIn: Bool
    var supportsBrightness: Bool
    var supportsVolume: Bool
    var brightness: Double
    var volume: Double
    var brightnessUnavailableReason: String?
    var volumeUnavailableReason: String?

    func supports(_ control: DisplayControlKind) -> Bool {
        switch control {
        case .brightness:
            supportsBrightness
        case .volume:
            supportsVolume
        }
    }

    func value(for control: DisplayControlKind) -> Double {
        switch control {
        case .brightness:
            brightness
        case .volume:
            volume
        }
    }

    mutating func setValue(_ value: Double, for control: DisplayControlKind) {
        switch control {
        case .brightness:
            brightness = value
        case .volume:
            volume = value
        }
    }

    mutating func setSupported(_ isSupported: Bool, for control: DisplayControlKind) {
        switch control {
        case .brightness:
            supportsBrightness = isSupported
            if isSupported {
                brightnessUnavailableReason = nil
            } else if brightnessUnavailableReason == nil {
                brightnessUnavailableReason = String(localized: "Display rejected brightness control.")
            }
        case .volume:
            supportsVolume = isSupported
            if isSupported {
                volumeUnavailableReason = nil
            } else if volumeUnavailableReason == nil {
                volumeUnavailableReason = String(localized: "Display rejected volume control.")
            }
        }
    }

    func unavailableReason(for control: DisplayControlKind) -> String? {
        switch control {
        case .brightness:
            brightnessUnavailableReason
        case .volume:
            volumeUnavailableReason
        }
    }
}

struct DisplayWriteResult: Equatable {
    let displayID: CGDirectDisplayID
    let control: DisplayControlKind
    let value: Double
    let success: Bool
}

final class DisplayControlService {
    private let displayServices = DynamicDisplayServicesBridge()
    private let ddc = DisplayDDCBridge()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func displays() -> [ControlledDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else {
            return []
        }

        let displayIDs = Array(ids.prefix(Int(count)))
        ddc.refresh(displayIDs: displayIDs)

        return displayIDs.map { id in
            let isBuiltIn = CGDisplayIsBuiltin(id) != 0
            let name = displayName(for: id, isBuiltIn: isBuiltIn)
            let storageID = displayStorageID(for: id, name: name, isBuiltIn: isBuiltIn)
            let appleBrightness = isBuiltIn ? displayServices.getBrightness(displayID: id) : nil
            let ddcBrightness = isBuiltIn ? nil : ddc.read(.brightness, displayID: id)
            let ddcVolume = isBuiltIn ? nil : ddc.read(.volume, displayID: id)
            let storedBrightness = storedValue(for: .brightness, storageID: storageID)
            let storedVolume = storedValue(for: .volume, storageID: storageID)
            let supportsBrightness = isBuiltIn ? appleBrightness != nil : ddcBrightness != nil
            let supportsVolume = !isBuiltIn && ddcVolume != nil

            return ControlledDisplay(
                id: id,
                storageID: storageID,
                name: name,
                isBuiltIn: isBuiltIn,
                supportsBrightness: supportsBrightness,
                supportsVolume: supportsVolume,
                brightness: appleBrightness.map { Double($0 * 100) }
                    ?? ddcBrightness
                    ?? storedBrightness
                    ?? DisplayControlKind.brightness.defaultValue,
                volume: ddcVolume
                    ?? storedVolume
                    ?? DisplayControlKind.volume.defaultValue,
                brightnessUnavailableReason: supportsBrightness ? nil : unavailableReason(
                    for: .brightness,
                    displayID: id,
                    isBuiltIn: isBuiltIn
                ),
                volumeUnavailableReason: supportsVolume ? nil : unavailableReason(
                    for: .volume,
                    displayID: id,
                    isBuiltIn: isBuiltIn
                )
            )
        }
    }

    func setValue(_ value: Double, for control: DisplayControlKind, display: ControlledDisplay) -> Bool {
        let clampedValue = Self.clamp(value)
        guard display.supports(control) else { return false }

        if display.isBuiltIn {
            guard control == .brightness else { return false }
            return displayServices.setBrightness(displayID: display.id, value: Float(clampedValue / 100))
        }

        let success = ddc.write(clampedValue, for: control, displayID: display.id)
        if success {
            saveStoredValue(clampedValue, for: control, storageID: display.storageID)
        }
        return success
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }

    private func displayName(for id: CGDirectDisplayID, isBuiltIn: Bool) -> String {
        if let names = displayServices.displayProductNames(displayID: id) {
            let localeID = Locale.current.identifier
            if let localized = names[localeID] ?? names["zh_CN"] ?? names["en_US"] ?? names.first?.value {
                return localized
            }
        }

        if isBuiltIn {
            return String(localized: "Built-in Display")
        }

        let model = CGDisplayModelNumber(id)
        return model == 0 ? String(localized: "External Display") : "\(String(localized: "External Display")) \(model)"
    }

    private func displayStorageID(for id: CGDirectDisplayID, name: String, isBuiltIn: Bool) -> String {
        let role = isBuiltIn ? "builtIn" : "external"
        return "\(role).\(name).\(CGDisplayVendorNumber(id)).\(CGDisplayModelNumber(id)).\(CGDisplaySerialNumber(id))"
    }

    private func storedValue(for control: DisplayControlKind, storageID: String) -> Double? {
        let key = storedValueKey(for: control, storageID: storageID)
        guard defaults.object(forKey: key) != nil else { return nil }
        return Self.clamp(defaults.double(forKey: key))
    }

    private func saveStoredValue(_ value: Double, for control: DisplayControlKind, storageID: String) {
        defaults.set(Self.clamp(value), forKey: storedValueKey(for: control, storageID: storageID))
    }

    private func storedValueKey(for control: DisplayControlKind, storageID: String) -> String {
        "displayControl.value.\(storageID).\(control.storageKey)"
    }

    private func unavailableReason(
        for control: DisplayControlKind,
        displayID: CGDirectDisplayID,
        isBuiltIn: Bool
    ) -> String {
        if isBuiltIn {
            switch control {
            case .brightness:
                return String(localized: "Built-in brightness interface is unavailable.")
            case .volume:
                return String(localized: "Built-in display has no display volume.")
            }
        }

        return ddc.unavailableReason(for: control, displayID: displayID)
    }
}

final class DisplayControlWorker {
    private let queue = DispatchQueue(label: "peakhalo.display-control", qos: .userInitiated)
    private var pendingWrites: [DisplayWriteKey: Double] = [:]
    private var debounceTimers: [DisplayWriteKey: DispatchWorkItem] = [:]
    private let debounceInterval: DispatchTimeInterval = .milliseconds(150)

    func refresh(service: DisplayControlService, completion: @escaping ([ControlledDisplay]) -> Void) {
        queue.async {
            completion(service.displays())
        }
    }

    func setValue(
        _ value: Double,
        control: DisplayControlKind,
        display: ControlledDisplay,
        service: DisplayControlService,
        completion: @escaping (DisplayWriteResult) -> Void
    ) {
        let key = DisplayWriteKey(displayID: display.id, control: control)
        queue.async {
            self.pendingWrites[key] = value
            self.debounceTimers[key]?.cancel()

            let timer = DispatchWorkItem { [service, display, key, completion] in
                guard let latestValue = self.pendingWrites.removeValue(forKey: key) else { return }
                self.debounceTimers.removeValue(forKey: key)
                let success = service.setValue(latestValue, for: key.control, display: display)
                completion(DisplayWriteResult(
                    displayID: key.displayID,
                    control: key.control,
                    value: latestValue,
                    success: success
                ))
            }
            self.debounceTimers[key] = timer
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: timer)
        }
    }
}

private struct DisplayWriteKey: Hashable {
    let displayID: CGDirectDisplayID
    let control: DisplayControlKind
}

private final class DynamicDisplayServicesBridge {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias DisplayInfo = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    private let resolver: DynamicFrameworkResolver
    private let getBrightnessSymbol: GetBrightness?
    private let setBrightnessSymbol: SetBrightness?
    private let displayInfoSymbol: DisplayInfo?

    init() {
        resolver = DynamicFrameworkResolver(paths: DynamicFrameworkPaths.displayServicePaths)
        getBrightnessSymbol = resolver.symbol("DisplayServicesGetBrightness")
        setBrightnessSymbol = resolver.symbol("DisplayServicesSetBrightness")
        displayInfoSymbol = resolver.symbol("CoreDisplay_DisplayCreateInfoDictionary")
    }

    func getBrightness(displayID: CGDirectDisplayID) -> Float? {
        guard let getBrightnessSymbol else { return nil }
        var value: Float = -1
        let result = getBrightnessSymbol(displayID, &value)
        guard result == 0, value >= 0 else { return nil }
        return min(1, max(0, value))
    }

    func setBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let setBrightnessSymbol else { return false }
        return setBrightnessSymbol(displayID, min(1, max(0, value))) == 0
    }

    func displayProductNames(displayID: CGDirectDisplayID) -> [String: String]? {
        guard let displayInfoSymbol,
              let info = displayInfoSymbol(displayID)?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return info["DisplayProductName"] as? [String: String]
    }
}

private final class DisplayDDCBridge {
    private typealias IOAVServiceRef = CFTypeRef
    private typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<IOAVServiceRef>?
    private typealias ReadI2C = @convention(c) (IOAVServiceRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias WriteI2C = @convention(c) (IOAVServiceRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private let resolver: DynamicFrameworkResolver
    private let createWithService: CreateWithService?
    private let readI2C: ReadI2C?
    private let writeI2C: WriteI2C?
    private var servicesByDisplayID: [CGDirectDisplayID: IOAVServiceRef] = [:]
    private var maxValues: [DisplayWriteKey: UInt16] = [:]
    private var refreshStatus: DDCRefreshStatus = .notRefreshed

    init() {
        resolver = DynamicFrameworkResolver(paths: DynamicFrameworkPaths.ddcPaths)
        createWithService = resolver.symbol("IOAVServiceCreateWithService")
        readI2C = resolver.symbol("IOAVServiceReadI2C")
        writeI2C = resolver.symbol("IOAVServiceWriteI2C")
    }

    func refresh(displayIDs: [CGDirectDisplayID]) {
        #if arch(arm64)
        let externalDisplayIDs = displayIDs.filter { CGDisplayIsBuiltin($0) == 0 }
        guard createWithService != nil, readI2C != nil, writeI2C != nil else {
            servicesByDisplayID = [:]
            refreshStatus = .symbolsUnavailable
            return
        }

        let services = avServices()
        guard !externalDisplayIDs.isEmpty else {
            servicesByDisplayID = [:]
            refreshStatus = .ready
            return
        }

        guard !services.isEmpty else {
            servicesByDisplayID = [:]
            refreshStatus = .noExternalService
            return
        }

        guard services.count == externalDisplayIDs.count else {
            servicesByDisplayID = [:]
            refreshStatus = .serviceCountMismatch(displayCount: externalDisplayIDs.count, serviceCount: services.count)
            return
        }

        servicesByDisplayID = Dictionary(uniqueKeysWithValues: zip(externalDisplayIDs, services))
        refreshStatus = .ready
        #else
        servicesByDisplayID = [:]
        refreshStatus = .unsupportedArchitecture
        #endif
    }

    func read(_ control: DisplayControlKind, displayID: CGDirectDisplayID) -> Double? {
        guard let service = servicesByDisplayID[displayID] else { return nil }
        for code in vcpCodes(for: control) {
            guard let values = read(service: service, vcpCode: code), values.max > 0 else {
                continue
            }
            let key = DisplayWriteKey(displayID: displayID, control: control)
            maxValues[key] = values.max
            return Double(min(values.current, values.max)) / Double(values.max) * 100
        }
        return nil
    }

    func unavailableReason(for control: DisplayControlKind, displayID: CGDirectDisplayID) -> String {
        guard servicesByDisplayID[displayID] != nil else {
            return refreshStatus.reason
        }

        switch control {
        case .brightness:
            return String(localized: "DDC/CI brightness is not readable.")
        case .volume:
            return String(localized: "Display does not expose DDC/CI volume.")
        }
    }

    func write(_ value: Double, for control: DisplayControlKind, displayID: CGDirectDisplayID) -> Bool {
        guard let service = servicesByDisplayID[displayID] else { return false }
        let key = DisplayWriteKey(displayID: displayID, control: control)
        let maxValue = maxValues[key] ?? 100
        var ddcValue = UInt16((DisplayControlService.clamp(value) / 100 * Double(maxValue)).rounded())
        if control == .volume, value > 0 {
            ddcValue = max(1, ddcValue)
        }

        if control == .volume, value <= 0 {
            _ = write(service: service, vcpCode: 0x8D, value: 1)
        } else if control == .volume {
            _ = write(service: service, vcpCode: 0x8D, value: 2)
        }

        return vcpCodes(for: control).contains { code in
            write(service: service, vcpCode: code, value: ddcValue)
        }
    }

    private func avServices() -> [IOAVServiceRef] {
        guard createWithService != nil else { return [] }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(root) }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var services: [IOAVServiceRef] = []
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }

            let namePointer = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
            defer { namePointer.deallocate() }
            guard IORegistryEntryGetName(entry, namePointer) == KERN_SUCCESS else { continue }
            let name = String(cString: namePointer)
            guard name.contains("DCPAVServiceProxy"),
                  registryString(entry, key: "Location") == "External",
                  let service = createWithService?(kCFAllocatorDefault, entry)?.takeRetainedValue() else {
                continue
            }
            services.append(service)
        }
        return services
    }

    private func read(service: IOAVServiceRef, vcpCode: UInt8) -> (current: UInt16, max: UInt16)? {
        var send = [vcpCode]
        var reply = [UInt8](repeating: 0, count: 11)
        guard communicate(service: service, send: &send, reply: &reply) else { return nil }
        let maxValue = (UInt16(reply[6]) << 8) + UInt16(reply[7])
        let currentValue = (UInt16(reply[8]) << 8) + UInt16(reply[9])
        return (currentValue, maxValue)
    }

    private func write(service: IOAVServiceRef, vcpCode: UInt8, value: UInt16) -> Bool {
        var send = [vcpCode, UInt8(value >> 8), UInt8(value & 0xff)]
        var reply: [UInt8] = []
        return communicate(service: service, send: &send, reply: &reply)
    }

    private func communicate(service: IOAVServiceRef, send: inout [UInt8], reply: inout [UInt8]) -> Bool {
        guard let readI2C, let writeI2C else { return false }
        let sevenBitAddress: UInt8 = 0x37
        let dataAddress: UInt8 = 0x51
        var packet = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let checksumSeed = send.count == 1 ? sevenBitAddress << 1 : sevenBitAddress << 1 ^ dataAddress
        packet[packet.count - 1] = checksum(seed: checksumSeed, data: packet, end: packet.count - 2)

        for _ in 0..<3 {
            usleep(10_000)
            let packetCount = UInt32(packet.count)
            let writeSuccess = packet.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return false }
                return writeI2C(service, UInt32(sevenBitAddress), UInt32(dataAddress), baseAddress, packetCount) == KERN_SUCCESS
            }

            guard writeSuccess else { continue }
            guard !reply.isEmpty else { return true }

            usleep(50_000)
            let replyCount = UInt32(reply.count)
            let readSuccess = reply.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return false }
                return readI2C(service, UInt32(sevenBitAddress), 0, baseAddress, replyCount) == KERN_SUCCESS
            }
            if readSuccess,
               reply.count >= 2,
               checksum(seed: 0x50, data: reply, end: reply.count - 2) == reply[reply.count - 1] {
                return true
            }
        }

        return false
    }

    private func checksum(seed: UInt8, data: [UInt8], end: Int) -> UInt8 {
        guard end >= 0 else { return seed }
        return data[0...end].reduce(seed) { $0 ^ $1 }
    }

    private func vcpCodes(for control: DisplayControlKind) -> [UInt8] {
        switch control {
        case .brightness:
            [0x10, 0x13]
        case .volume:
            [0x62]
        }
    }

    private func registryString(_ service: io_service_t, key: String) -> String? {
        IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
    }
}

private enum DynamicFrameworkPaths {
    static let displayServicePaths = [
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        "/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay"
    ]

    static let ddcPaths = [
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        "/System/Library/PrivateFrameworks/DisplayTransportServices.framework/DisplayTransportServices",
        "/System/Library/PrivateFrameworks/DSExternalDisplay.framework/DSExternalDisplay",
        "/System/Library/PrivateFrameworks/HIDDisplay.framework/HIDDisplay",
        "/System/Library/PrivateFrameworks/CoreDisplay.framework/CoreDisplay"
    ]
}

private final class DynamicFrameworkResolver {
    private let handles: [UnsafeMutableRawPointer]

    init(paths: [String]) {
        handles = paths.compactMap { dlopen($0, RTLD_LAZY) }
    }

    deinit {
        handles.forEach { dlclose($0) }
    }

    func symbol<T>(_ name: String) -> T? {
        for handle in handles {
            if let raw = dlsym(handle, name) {
                return unsafeBitCast(raw, to: T.self)
            }
        }
        return nil
    }
}

private enum DDCRefreshStatus: Equatable {
    case notRefreshed
    case ready
    case symbolsUnavailable
    case noExternalService
    case serviceCountMismatch(displayCount: Int, serviceCount: Int)
    case unsupportedArchitecture

    var reason: String {
        switch self {
        case .notRefreshed:
            return String(localized: "DDC/CI has not been checked.")
        case .ready:
            return String(localized: "DDC/CI does not support this control.")
        case .symbolsUnavailable:
            return String(localized: "System DDC/CI interface is unavailable.")
        case .noExternalService:
            return String(localized: "No external DDC/CI service was detected.")
        case let .serviceCountMismatch(displayCount, serviceCount):
            return String(
                format: String(localized: "Could not match DDC services: %d displays / %d services."),
                displayCount,
                serviceCount
            )
        case .unsupportedArchitecture:
            return String(localized: "DDC/CI is not supported on this architecture.")
        }
    }
}
