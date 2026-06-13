import Foundation

enum AudioRouteResolver {
    struct Resolution: Equatable {
        let route: AudioProcessTapRoute
        let usedFallback: Bool
    }

    static func processingGain(
        for item: AudioAppVolumeItem,
        outputDevices: [AudioOutputDevice],
        defaultOutputDevice: AudioOutputDevice?
    ) -> Double {
        switch item.outputRouteIntent {
        case .systemDefault:
            return defaultOutputDevice?.softwareProcessingGain ?? 1
        case .single(let outputDeviceUID):
            let device = outputDevices.first { $0.uid == outputDeviceUID } ?? defaultOutputDevice
            return device?.softwareProcessingGain ?? 1
        case .multi:
            return 1
        }
    }

    static func itemUsesSoftwareDeviceGain(
        _ item: AudioAppVolumeItem,
        deviceUID: String,
        outputDevices: [AudioOutputDevice],
        defaultOutputDevice: AudioOutputDevice?
    ) -> Bool {
        switch item.outputRouteIntent {
        case .systemDefault:
            return defaultOutputDevice?.uid == deviceUID
        case .single(let outputDeviceUID):
            if outputDevices.contains(where: { $0.uid == outputDeviceUID }) {
                return outputDeviceUID == deviceUID
            }
            return defaultOutputDevice?.uid == deviceUID
        case .multi:
            return false
        }
    }

    static func resolve(
        for item: AudioAppVolumeItem,
        outputDevices: [AudioOutputDevice],
        defaultOutputDevice: AudioOutputDevice?
    ) -> Resolution? {
        switch item.outputRouteIntent {
        case .single(let outputDeviceUID):
            if let device = outputDevices.first(where: { $0.uid == outputDeviceUID }) {
                return Resolution(
                    route: AudioProcessTapRoute(
                        outputDeviceID: device.id,
                        outputDeviceUID: device.uid,
                        outputDevices: [device],
                        followsSystemDefault: false,
                        preferredTapSourceDeviceUID: nil
                    ),
                    usedFallback: false
                )
            }

            if let defaultOutputDevice {
                return Resolution(
                    route: AudioProcessTapRoute(
                        outputDeviceID: defaultOutputDevice.id,
                        outputDeviceUID: defaultOutputDevice.uid,
                        outputDevices: [defaultOutputDevice],
                        followsSystemDefault: false,
                        preferredTapSourceDeviceUID: nil
                    ),
                    usedFallback: true
                )
            }

            return nil
        case .multi(let outputDeviceUIDs):
            let selectedDevices = outputDeviceUIDs.compactMap { uid in
                outputDevices.first { $0.uid == uid }
            }
            if let firstDevice = selectedDevices.first {
                return Resolution(
                    route: AudioProcessTapRoute(
                        outputDeviceID: firstDevice.id,
                        outputDeviceUID: firstDevice.uid,
                        outputDevices: selectedDevices,
                        followsSystemDefault: false,
                        preferredTapSourceDeviceUID: nil
                    ),
                    usedFallback: false
                )
            }

            if let defaultOutputDevice {
                return Resolution(
                    route: AudioProcessTapRoute(
                        outputDeviceID: defaultOutputDevice.id,
                        outputDeviceUID: defaultOutputDevice.uid,
                        outputDevices: [defaultOutputDevice],
                        followsSystemDefault: false,
                        preferredTapSourceDeviceUID: nil
                    ),
                    usedFallback: true
                )
            }

            return nil
        case .systemDefault:
            guard let defaultOutputDevice else { return nil }
            return Resolution(
                route: AudioProcessTapRoute(
                    outputDeviceID: defaultOutputDevice.id,
                    outputDeviceUID: defaultOutputDevice.uid,
                    outputDevices: [defaultOutputDevice],
                    followsSystemDefault: true,
                    preferredTapSourceDeviceUID: defaultOutputDevice.uid
                ),
                usedFallback: false
            )
        }
    }
}
