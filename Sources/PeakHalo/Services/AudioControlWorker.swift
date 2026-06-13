import CoreAudio
import Foundation

final class AudioControlWorker {
    private let queue = DispatchQueue(label: "peakhalo.audio-control", qos: .userInitiated)
    private var pendingDeviceVolumeWrites: [AudioObjectID: Double] = [:]
    private var deviceVolumeTimers: [AudioObjectID: DispatchWorkItem] = [:]
    private let deviceVolumeDebounce: DispatchTimeInterval = .milliseconds(150)

    struct RefreshResult {
        let devices: [AudioOutputDevice]
        let audioProcesses: [AudioProcessInfo]
    }

    struct DeviceVolumeWriteResult {
        let deviceID: AudioObjectID
        let value: Double
        let success: Bool
        let actualValue: Double?
        let actualIsMuted: Bool?
    }

    struct DeviceMuteWriteResult {
        let deviceID: AudioObjectID
        let isMuted: Bool
        let success: Bool
        let actualValue: Double?
        let actualIsMuted: Bool?
    }

    func refresh(
        service: SystemAudioVolumeService,
        processService: AudioProcessService,
        includeAudioProcesses: Bool,
        completion: @escaping (RefreshResult) -> Void
    ) {
        queue.async {
            completion(RefreshResult(
                devices: service.outputDevices(),
                audioProcesses: includeAudioProcesses ? processService.audibleProcesses() : []
            ))
        }
    }

    func setDeviceVolume(
        _ value: Double,
        deviceID: AudioObjectID,
        service: SystemAudioVolumeService,
        completion: @escaping (DeviceVolumeWriteResult) -> Void
    ) {
        queue.async {
            if let pendingValue = self.pendingDeviceVolumeWrites[deviceID],
               abs(pendingValue - value) < 0.05 {
                return
            }

            self.pendingDeviceVolumeWrites[deviceID] = value
            self.deviceVolumeTimers[deviceID]?.cancel()

            let timer = DispatchWorkItem { [weak self, service] in
                guard let self,
                      let latestValue = self.pendingDeviceVolumeWrites.removeValue(forKey: deviceID) else {
                    return
                }
                self.deviceVolumeTimers.removeValue(forKey: deviceID)

                let write = service.setDeviceVolumeAndReadState(latestValue, deviceID: deviceID)
                completion(DeviceVolumeWriteResult(
                    deviceID: deviceID,
                    value: latestValue,
                    success: write.success,
                    actualValue: write.actualVolume ?? (write.success ? latestValue : nil),
                    actualIsMuted: write.actualIsMuted
                ))
            }
            self.deviceVolumeTimers[deviceID] = timer
            self.queue.asyncAfter(deadline: .now() + self.deviceVolumeDebounce, execute: timer)
        }
    }

    func setDeviceMuted(
        _ isMuted: Bool,
        deviceID: AudioObjectID,
        service: SystemAudioVolumeService,
        completion: @escaping (DeviceMuteWriteResult) -> Void
    ) {
        queue.async {
            self.deviceVolumeTimers[deviceID]?.cancel()
            self.deviceVolumeTimers.removeValue(forKey: deviceID)
            self.pendingDeviceVolumeWrites.removeValue(forKey: deviceID)

            let write = service.setDeviceMutedAndReadState(isMuted, deviceID: deviceID)
            completion(DeviceMuteWriteResult(
                deviceID: deviceID,
                isMuted: isMuted,
                success: write.success,
                actualValue: write.actualVolume,
                actualIsMuted: write.actualIsMuted
            ))
        }
    }
}
