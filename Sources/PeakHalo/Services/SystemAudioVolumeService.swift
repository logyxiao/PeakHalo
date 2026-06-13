import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation

final class SystemAudioVolumeService {
    private enum DeviceVolumeBackend {
        case hardware
        case display(ControlledDisplay)
        case software(String)
        case unavailable

        var supportsVolume: Bool {
            switch self {
            case .hardware, .display, .software:
                return true
            case .unavailable:
                return false
            }
        }

        var unavailableReason: String? {
            switch self {
            case .hardware, .display, .software:
                return nil
            case .unavailable:
                return String(localized: "This output device does not expose CoreAudio or DDC/CI volume.")
            }
        }

        var kind: AudioOutputVolumeBackend {
            switch self {
            case .hardware:
                return .hardware
            case .display:
                return .display
            case .software:
                return .software
            case .unavailable:
                return .unavailable
            }
        }

        func supportsMute(deviceID: AudioObjectID, service: SystemAudioVolumeService) -> Bool {
            switch self {
            case .hardware:
                return service.canSetMute(deviceID: deviceID)
            case .display, .software:
                return true
            case .unavailable:
                return false
            }
        }
    }

    private let displayControlService = DisplayControlService()
    private let defaults: UserDefaults
    private let monitorQueue = DispatchQueue(label: "peakhalo.audio-device-monitor")
    private var cachedBackends: [AudioObjectID: DeviceVolumeBackend] = [:]
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func startDeviceMonitoring(onChange: @escaping @Sendable () -> Void) {
        guard deviceListListener == nil, defaultOutputListener == nil else { return }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceListListener: AudioObjectPropertyListenerBlock = { _, _ in
            onChange()
        }
        let defaultOutputListener: AudioObjectPropertyListenerBlock = { _, _ in
            onChange()
        }

        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        if AudioObjectAddPropertyListenerBlock(
            systemObjectID,
            &devicesAddress,
            monitorQueue,
            deviceListListener
        ) == noErr {
            self.deviceListListener = deviceListListener
        }

        if AudioObjectAddPropertyListenerBlock(
            systemObjectID,
            &defaultOutputAddress,
            monitorQueue,
            defaultOutputListener
        ) == noErr {
            self.defaultOutputListener = defaultOutputListener
        }
    }

    func stopDeviceMonitoring() {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

        if let deviceListListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                systemObjectID,
                &address,
                monitorQueue,
                deviceListListener
            )
            self.deviceListListener = nil
        }

        if let defaultOutputListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                systemObjectID,
                &address,
                monitorQueue,
                defaultOutputListener
            )
            self.defaultOutputListener = nil
        }
    }

    func outputDevices() -> [AudioOutputDevice] {
        let defaultID = defaultOutputDeviceID()
        let displays = displayControlService.displays()

        let outputDeviceIDs = audioDevices().filter(hasOutputStreams)
        var nextBackends: [AudioObjectID: DeviceVolumeBackend] = [:]

        let devices = outputDeviceIDs.map { deviceID in
            let uid = stringProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceUID
            ) ?? "\(deviceID)"
            let name = stringProperty(
                objectID: deviceID,
                selector: kAudioObjectPropertyName
            ) ?? String(localized: "Output Device")
            let transportType = transportType(deviceID: deviceID)
            let backend = volumeBackend(
                deviceID: deviceID,
                uid: uid,
                name: name,
                transportType: transportType,
                displays: displays
            )
            nextBackends[deviceID] = backend
            let volume = deviceVolume(deviceID: deviceID, backend: backend)
            let supportsVolume = backend.supportsVolume
            let supportsMute = backend.supportsMute(deviceID: deviceID, service: self)

            return AudioOutputDevice(
                id: deviceID,
                uid: uid,
                name: name,
                transportName: transportName(for: transportType),
                isDefault: deviceID == defaultID,
                volume: volume ?? DisplayControlKind.volume.defaultValue,
                isMuted: deviceMuted(deviceID: deviceID, backend: backend),
                volumeBackend: backend.kind,
                supportsVolume: supportsVolume,
                supportsMute: supportsMute,
                unavailableReason: backend.unavailableReason
            )
        }
        cachedBackends = nextBackends
        return devices
    }

    func outputVolume() -> Double? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        let uid = stringProperty(objectID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "\(deviceID)"
        let name = stringProperty(objectID: deviceID, selector: kAudioObjectPropertyName) ?? String(localized: "Output Device")
        let backend = volumeBackend(
            deviceID: deviceID,
            uid: uid,
            name: name,
            transportType: transportType(deviceID: deviceID),
            displays: displayControlService.displays()
        )
        return deviceVolume(deviceID: deviceID, backend: backend)
    }

    func setOutputVolume(_ value: Double) -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return setDeviceVolume(value, deviceID: deviceID)
    }

    func setDeviceVolume(_ value: Double, deviceID: AudioObjectID) -> Bool {
        setDeviceVolumeAndReadState(value, deviceID: deviceID).success
    }

    func setDeviceVolumeAndReadState(
        _ value: Double,
        deviceID: AudioObjectID
    ) -> (success: Bool, actualVolume: Double?, actualIsMuted: Bool?) {
        let clampedValue = Self.clamp(value)
        let scalar = Float(clampedValue / 100)
        var backend = cachedBackend(for: deviceID)
        let success: Bool

        switch backend {
        case .hardware:
            success = setHardwareVolume(deviceID: deviceID, value: scalar)
            if success {
                if clampedValue <= 0 {
                    _ = setCoreAudioMuted(true, deviceID: deviceID)
                } else {
                    _ = setCoreAudioMuted(false, deviceID: deviceID)
                }
            }
        case .display(let display):
            success = displayControlService.setValue(clampedValue, for: .volume, display: display)
            if success {
                var updatedDisplay = display
                updatedDisplay.volume = clampedValue
                backend = .display(updatedDisplay)
                cachedBackends[deviceID] = backend
            }
        case .software(let uid):
            setSoftwareVolume(clampedValue, uid: uid)
            success = true
        case .unavailable:
            success = false
        }

        guard success else {
            let state = deviceState(deviceID: deviceID)
            return (false, state.volume, state.isMuted)
        }

        return (
            true,
            clampedValue,
            backend.supportsMute(deviceID: deviceID, service: self)
                ? deviceMuted(deviceID: deviceID, backend: backend)
                : nil
        )
    }

    private func setHardwareVolume(deviceID: AudioObjectID, value: Float32) -> Bool {
        if setVirtualMainVolume(deviceID: deviceID, value: value) {
            return true
        }

        if setVolume(deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: value) {
            return true
        }

        let left = setVolume(deviceID: deviceID, element: 1, value: value)
        let right = setVolume(deviceID: deviceID, element: 2, value: value)
        return left || right
    }

    func setDeviceMuted(_ isMuted: Bool, deviceID: AudioObjectID) -> Bool {
        setDeviceMutedAndReadState(isMuted, deviceID: deviceID).success
    }

    func setDeviceMutedAndReadState(
        _ isMuted: Bool,
        deviceID: AudioObjectID
    ) -> (success: Bool, actualVolume: Double?, actualIsMuted: Bool?) {
        var backend = cachedBackend(for: deviceID)
        let success: Bool
        var actualVolume: Double?

        switch backend {
        case .display(let display):
            actualVolume = displayControlService.volumeAfterSettingMuted(isMuted, for: display)
            success = displayControlService.setVolumeMuted(isMuted, for: display)
            if success, let actualVolume {
                var updatedDisplay = display
                updatedDisplay.volume = actualVolume
                backend = .display(updatedDisplay)
                cachedBackends[deviceID] = backend
            }
        case .hardware:
            success = setCoreAudioMuted(isMuted, deviceID: deviceID)
            actualVolume = coreAudioVolume(deviceID: deviceID)
        case .software(let uid):
            actualVolume = setSoftwareMuted(isMuted, uid: uid)
            success = true
        case .unavailable:
            success = false
        }

        guard success else {
            let state = deviceState(deviceID: deviceID)
            return (false, state.volume, state.isMuted)
        }

        return (true, actualVolume, isMuted)
    }

    private func setCoreAudioMuted(_ isMuted: Bool, deviceID: AudioObjectID) -> Bool {
        if setMuted(deviceID: deviceID, element: kAudioObjectPropertyElementMain, isMuted: isMuted) {
            return true
        }

        let left = setMuted(deviceID: deviceID, element: 1, isMuted: isMuted)
        let right = setMuted(deviceID: deviceID, element: 2, isMuted: isMuted)
        return left || right
    }

    func setDefaultOutputDevice(_ deviceID: AudioObjectID) -> Bool {
        var mutableDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var isSettable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            &isSettable
        ) == noErr,
              isSettable.boolValue else {
            return false
        }

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &mutableDeviceID
        )
        return status == noErr
    }

    func defaultOutputDeviceID() -> AudioObjectID? {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    func deviceState(deviceID: AudioObjectID) -> (volume: Double?, isMuted: Bool?) {
        let backend = cachedBackend(for: deviceID)
        return (
            deviceVolume(deviceID: deviceID, backend: backend),
            backend.supportsMute(deviceID: deviceID, service: self)
                ? deviceMuted(deviceID: deviceID, backend: backend)
                : nil
        )
    }

    func outputProcessingGain(for deviceID: AudioObjectID) -> Double {
        switch cachedBackend(for: deviceID) {
        case .software(let uid):
            return softwareProcessingGain(uid: uid)
        case .hardware, .display, .unavailable:
            return 1
        }
    }

    private func audioDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr,
              size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var devices = [AudioObjectID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        )
        guard status == noErr else { return [] }
        return devices
    }

    private func hasOutputStreams(deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return false
        }
        return size > 0
    }

    private func deviceVolume(deviceID: AudioObjectID, backend: DeviceVolumeBackend) -> Double? {
        switch backend {
        case .display(let display):
            return display.volume
        case .software(let uid):
            return softwareVolume(uid: uid)
        case .hardware, .unavailable:
            return coreAudioVolume(deviceID: deviceID)
        }
    }

    private func deviceMuted(deviceID: AudioObjectID, backend: DeviceVolumeBackend) -> Bool {
        switch backend {
        case .display(let display):
            return displayControlService.isVolumeMuted(for: display)
        case .hardware:
            return isMuted(deviceID: deviceID) ?? false
        case .software(let uid):
            return softwareMuted(uid: uid)
        case .unavailable:
            return false
        }
    }

    private func coreAudioVolume(deviceID: AudioObjectID) -> Double? {
        if let virtualMain = virtualMainVolume(deviceID: deviceID) {
            return virtualMain * 100
        }

        if let master = volume(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return master * 100
        }

        let channels = [UInt32(1), UInt32(2)].compactMap {
            volume(deviceID: deviceID, element: $0)
        }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Double(channels.count) * 100
    }

    private func virtualMainVolume(deviceID: AudioObjectID) -> Double? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return Double(min(1, max(0, value)))
    }

    private func volume(deviceID: AudioObjectID, element: AudioObjectPropertyElement) -> Double? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return Double(min(1, max(0, value)))
    }

    private func canSetVolume(deviceID: AudioObjectID) -> Bool {
        isSettable(
            objectID: deviceID,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioObjectPropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
            || volume(deviceID: deviceID, element: kAudioObjectPropertyElementMain) != nil
            && isSettable(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput,
                element: kAudioObjectPropertyElementMain
            )
            || [UInt32(1), UInt32(2)].contains {
                volume(deviceID: deviceID, element: $0) != nil
                    && isSettable(
                        objectID: deviceID,
                        selector: kAudioDevicePropertyVolumeScalar,
                        scope: kAudioDevicePropertyScopeOutput,
                        element: $0
                    )
            }
    }

    private func setVirtualMainVolume(deviceID: AudioObjectID, value: Float32) -> Bool {
        var mutableValue = min(1, max(0, value))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var isSettable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            return false
        }

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &mutableValue
        )
        return status == noErr
    }

    private func setVolume(
        deviceID: AudioObjectID,
        element: AudioObjectPropertyElement,
        value: Float32
    ) -> Bool {
        var mutableValue = min(1, max(0, value))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var isSettable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            return false
        }

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &mutableValue
        )
        return status == noErr
    }

    private func isMuted(deviceID: AudioObjectID) -> Bool? {
        if let master = muted(deviceID: deviceID, element: kAudioObjectPropertyElementMain) {
            return master
        }

        let channels = [UInt32(1), UInt32(2)].compactMap {
            muted(deviceID: deviceID, element: $0)
        }
        guard !channels.isEmpty else { return nil }
        return channels.allSatisfy { $0 }
    }

    private func muted(deviceID: AudioObjectID, element: AudioObjectPropertyElement) -> Bool? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return value != 0
    }

    private func canSetMute(deviceID: AudioObjectID) -> Bool {
        isSettable(
            objectID: deviceID,
            selector: kAudioDevicePropertyMute,
            scope: kAudioDevicePropertyScopeOutput,
            element: kAudioObjectPropertyElementMain
        )
        || [UInt32(1), UInt32(2)].contains {
            isSettable(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput,
                element: $0
            )
        }
    }

    private func setMuted(
        deviceID: AudioObjectID,
        element: AudioObjectPropertyElement,
        isMuted: Bool
    ) -> Bool {
        var value = isMuted ? UInt32(1) : UInt32(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
              settable.boolValue else {
            return false
        }

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        )
        return status == noErr
    }

    private func volumeBackend(
        deviceID: AudioObjectID,
        uid: String,
        name: String,
        transportType: UInt32?,
        displays: [ControlledDisplay]
    ) -> DeviceVolumeBackend {
        let ddcDisplay = matchingDDCDisplay(
            uid: uid,
            name: name,
            transportType: transportType,
            displays: displays
        )

        if isDisplayTransport(transportType), let ddcDisplay {
            return .display(ddcDisplay)
        }

        if canSetVolume(deviceID: deviceID) {
            return .hardware
        }

        if let ddcDisplay {
            return .display(ddcDisplay)
        }

        return .software(uid)
    }

    private func cachedBackend(for deviceID: AudioObjectID) -> DeviceVolumeBackend {
        if let backend = cachedBackends[deviceID] {
            return backend
        }

        let uid = stringProperty(objectID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "\(deviceID)"
        let name = stringProperty(objectID: deviceID, selector: kAudioObjectPropertyName) ?? String(localized: "Output Device")
        let backend = volumeBackend(
            deviceID: deviceID,
            uid: uid,
            name: name,
            transportType: transportType(deviceID: deviceID),
            displays: displayControlService.displays()
        )
        cachedBackends[deviceID] = backend
        return backend
    }

    private func matchingDDCDisplay(
        uid: String,
        name: String,
        transportType: UInt32?,
        displays: [ControlledDisplay]
    ) -> ControlledDisplay? {
        let candidates = displays.filter { !$0.isBuiltIn && $0.supportsVolume }
        guard !candidates.isEmpty else { return nil }

        if let namedMatch = candidates.first(where: { displayNamesMatch(name, $0.name) }) {
            return namedMatch
        }

        if let uidMatch = candidates.first(where: { displayIDMatchesAudioUID($0.id, uid: uid) }) {
            return uidMatch
        }

        if candidates.count == 1, isDisplayTransport(transportType) {
            return candidates[0]
        }

        return nil
    }

    private func displayNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedDisplayName(lhs)
        let right = normalizedDisplayName(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.contains(right) || right.contains(left)
    }

    private func normalizedDisplayName(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func displayIDMatchesAudioUID(_ displayID: CGDirectDisplayID, uid: String) -> Bool {
        let normalizedUID = uid.lowercased()
        let vendor = UInt32(CGDisplayVendorNumber(displayID))
        let model = UInt32(CGDisplayModelNumber(displayID))
        guard vendor > 0, model > 0 else { return false }

        let directPrefix = String(format: "%04x%04x", vendor, model)
        let swappedModel = ((model & 0xff) << 8) | ((model >> 8) & 0xff)
        let swappedPrefix = String(format: "%04x%04x", vendor, swappedModel)

        return normalizedUID.hasPrefix(directPrefix) || normalizedUID.hasPrefix(swappedPrefix)
    }

    private func isDisplayTransport(_ type: UInt32?) -> Bool {
        switch type {
        case kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort,
             kAudioDeviceTransportTypeThunderbolt:
            return true
        default:
            return false
        }
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                pointer
            )
        }
        guard status == noErr else { return nil }
        return value as String
    }

    private func transportType(deviceID: AudioObjectID) -> UInt32? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return value
    }

    private func transportName(for type: UInt32?) -> String {
        switch type {
        case kAudioDeviceTransportTypeBuiltIn:
            return String(localized: "Built-in")
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        case kAudioDeviceTransportTypeAirPlay:
            return "AirPlay"
        case kAudioDeviceTransportTypeThunderbolt:
            return "Thunderbolt"
        case kAudioDeviceTransportTypeVirtual:
            return String(localized: "Virtual")
        case kAudioDeviceTransportTypeAggregate:
            return String(localized: "Aggregate")
        default:
            return String(localized: "Output")
        }
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }

    private func softwareVolume(uid: String) -> Double {
        if let value = defaults.object(forKey: softwareVolumeKey(uid)) as? Double {
            return Self.clamp(value)
        }

        if let value = defaults.object(forKey: softwareVolumeKey(uid)) as? NSNumber {
            return Self.clamp(value.doubleValue)
        }

        return softwareMutedFlag(uid: uid) ? 0 : 100
    }

    private func softwareMuted(uid: String) -> Bool {
        softwareMutedFlag(uid: uid) || softwareVolume(uid: uid) <= 0
    }

    private func softwareMutedFlag(uid: String) -> Bool {
        defaults.bool(forKey: softwareMuteKey(uid))
    }

    private func softwareProcessingGain(uid: String) -> Double {
        guard !softwareMuted(uid: uid) else { return 0 }
        return min(1, max(0, softwareVolume(uid: uid) / 100))
    }

    private func setSoftwareVolume(_ value: Double, uid: String) {
        let clampedValue = Self.clamp(value)
        defaults.set(clampedValue, forKey: softwareVolumeKey(uid))

        if clampedValue > 0 {
            defaults.set(clampedValue, forKey: softwareRestoreVolumeKey(uid))
            defaults.set(false, forKey: softwareMuteKey(uid))
        } else {
            defaults.set(true, forKey: softwareMuteKey(uid))
        }
    }

    @discardableResult
    private func setSoftwareMuted(_ isMuted: Bool, uid: String) -> Double {
        if isMuted {
            let currentVolume = softwareVolume(uid: uid)
            if currentVolume > 0 {
                defaults.set(currentVolume, forKey: softwareRestoreVolumeKey(uid))
            }
            defaults.set(0.0, forKey: softwareVolumeKey(uid))
            defaults.set(true, forKey: softwareMuteKey(uid))
            return 0
        }

        defaults.set(false, forKey: softwareMuteKey(uid))

        let currentVolume = softwareVolume(uid: uid)
        guard currentVolume <= 0 else { return currentVolume }

        let restoredVolume = Self.clamp(
            (defaults.object(forKey: softwareRestoreVolumeKey(uid)) as? Double)
                ?? (defaults.object(forKey: softwareRestoreVolumeKey(uid)) as? NSNumber)?.doubleValue
                ?? 50
        )
        let visibleVolume = restoredVolume > 0 ? restoredVolume : 50
        defaults.set(visibleVolume, forKey: softwareVolumeKey(uid))
        return visibleVolume
    }

    private func softwareVolumeKey(_ uid: String) -> String {
        "audio.softwareDevice.volume.\(uid)"
    }

    private func softwareMuteKey(_ uid: String) -> String {
        "audio.softwareDevice.muted.\(uid)"
    }

    private func softwareRestoreVolumeKey(_ uid: String) -> String {
        "audio.softwareDevice.restoreVolume.\(uid)"
    }

    private func isSettable(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )

        guard AudioObjectHasProperty(objectID, &address) else { return false }
        var isSettable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(objectID, &address, &isSettable) == noErr
            && isSettable.boolValue
    }
}
