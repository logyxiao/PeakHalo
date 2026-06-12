import AudioToolbox
import CoreAudio
import Foundation

final class AudioProcessTapService {
    private final class RenderState {
        var gain: Float
        var isMuted: Bool

        init(volume: Double, isMuted: Bool, boost: AudioBoostLevel) {
            self.gain = Self.gain(volume: volume, isMuted: isMuted, boost: boost)
            self.isMuted = isMuted
        }

        func update(volume: Double, isMuted: Bool, boost: AudioBoostLevel) {
            self.gain = Self.gain(volume: volume, isMuted: isMuted, boost: boost)
            self.isMuted = isMuted
        }

        private static func gain(volume: Double, isMuted: Bool, boost: AudioBoostLevel) -> Float {
            guard !isMuted else { return 0 }
            let clampedVolume = min(100, max(0, volume))
            return Float((clampedVolume / 100) * boost.rawValue)
        }
    }

    private struct ActiveTap {
        let itemID: String
        let processObjectIDs: [AudioObjectID]
        let tapID: AudioObjectID
        let aggregateDeviceID: AudioObjectID
        let deviceProcID: AudioDeviceIOProcID
        let description: CATapDescription
        let renderState: RenderState
    }

    private let queue = DispatchQueue(label: "peakhalo.audio-process-tap", qos: .userInitiated)
    private var activeTaps: [String: ActiveTap] = [:]

    deinit {
        deactivateAll()
    }

    func activate(
        itemID: String,
        processObjectIDs: [AudioObjectID],
        outputDeviceUID: String?,
        volume: Double,
        isMuted: Bool,
        boost: AudioBoostLevel,
        completion: @escaping (AudioProcessTapResult) -> Void
    ) {
        queue.async {
            guard #available(macOS 14.2, *) else {
                completion(AudioProcessTapResult(
                    itemID: itemID,
                    success: false,
                    message: String(localized: "Process taps require macOS 14.2 or later.")
                ))
                return
            }

            guard let outputDeviceUID else {
                completion(AudioProcessTapResult(
                    itemID: itemID,
                    success: false,
                    message: String(localized: "No output device is available for audio processing.")
                ))
                return
            }

            guard !processObjectIDs.isEmpty else {
                completion(AudioProcessTapResult(
                    itemID: itemID,
                    success: false,
                    message: String(localized: "No active audio process is available for this app.")
                ))
                return
            }

            if let activeTap = self.activeTaps[itemID] {
                activeTap.renderState.update(volume: volume, isMuted: isMuted, boost: boost)
                completion(AudioProcessTapResult(itemID: itemID, success: true, message: nil))
                return
            }

            do {
                let activeTap = try self.createActiveTap(
                    itemID: itemID,
                    processObjectIDs: processObjectIDs,
                    outputDeviceUID: outputDeviceUID,
                    volume: volume,
                    isMuted: isMuted,
                    boost: boost
                )
                self.activeTaps[itemID] = activeTap
                completion(AudioProcessTapResult(itemID: itemID, success: true, message: nil))
            } catch {
                let statusCode = Self.statusCode(from: error)
                completion(AudioProcessTapResult(
                    itemID: itemID,
                    success: false,
                    message: error.localizedDescription,
                    statusCode: statusCode
                ))
            }
        }
    }

    func update(
        itemID: String,
        volume: Double,
        isMuted: Bool,
        boost: AudioBoostLevel
    ) {
        queue.async {
            self.activeTaps[itemID]?.renderState.update(volume: volume, isMuted: isMuted, boost: boost)
        }
    }

    func deactivate(
        itemID: String,
        completion: @escaping (AudioProcessTapResult) -> Void
    ) {
        queue.async {
            guard let tap = self.activeTaps.removeValue(forKey: itemID) else {
                completion(AudioProcessTapResult(itemID: itemID, success: true, message: nil))
                return
            }

            let status = self.destroy(tap)
            completion(AudioProcessTapResult(
                itemID: itemID,
                success: status == noErr,
                message: status == noErr ? nil : String(
                    format: String(localized: "Could not destroy audio processing chain (%d)."),
                    Int(status)
                )
            ))
        }
    }

    func deactivateAll() {
        queue.sync {
            for tap in activeTaps.values {
                _ = destroy(tap)
            }
            activeTaps.removeAll()
        }
    }

    @available(macOS 14.2, *)
    private func createActiveTap(
        itemID: String,
        processObjectIDs: [AudioObjectID],
        outputDeviceUID: String,
        volume: Double,
        isMuted: Bool,
        boost: AudioBoostLevel
    ) throws -> ActiveTap {
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        tapDescription.uuid = UUID()
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .mutedWhenTapped

        var tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard status == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
            throw audioError("Could not create process tap (%d).", status)
        }

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateDescription = aggregateDeviceDescription(
            outputDeviceUID: outputDeviceUID,
            tapUUID: tapDescription.uuid,
            itemID: itemID
        )
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != AudioObjectID(kAudioObjectUnknown) else {
            AudioHardwareDestroyProcessTap(tapID)
            throw audioError("Could not create aggregate device (%d).", status)
        }

        let renderState = RenderState(volume: volume, isMuted: isMuted, boost: boost)
        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inputData, _, outputData, _ in
            Self.render(inputData: inputData, outputData: outputData, state: renderState)
        }
        guard status == noErr, let procID else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            throw audioError("Could not create audio processing callback (%d).", status)
        }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            throw audioError("Could not start audio processing (%d).", status)
        }

        return ActiveTap(
            itemID: itemID,
            processObjectIDs: processObjectIDs,
            tapID: tapID,
            aggregateDeviceID: aggregateID,
            deviceProcID: procID,
            description: tapDescription,
            renderState: renderState
        )
    }

    private func aggregateDeviceDescription(
        outputDeviceUID: String,
        tapUUID: UUID,
        itemID: String
    ) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "PeakHalo-\(itemID)",
            kAudioAggregateDeviceUIDKey: "com.logyxiao.PeakHalo.audio.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputDeviceUID,
                    kAudioSubDeviceDriftCompensationKey: false
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]
    }

    private func destroy(_ tap: ActiveTap) -> OSStatus {
        var finalStatus = noErr

        let stopStatus = AudioDeviceStop(tap.aggregateDeviceID, tap.deviceProcID)
        if stopStatus != noErr {
            finalStatus = stopStatus
        }

        let procStatus = AudioDeviceDestroyIOProcID(tap.aggregateDeviceID, tap.deviceProcID)
        if procStatus != noErr {
            finalStatus = procStatus
        }

        let aggregateStatus = AudioHardwareDestroyAggregateDevice(tap.aggregateDeviceID)
        if aggregateStatus != noErr {
            finalStatus = aggregateStatus
        }

        if #available(macOS 14.2, *) {
            let tapStatus = AudioHardwareDestroyProcessTap(tap.tapID)
            if tapStatus != noErr {
                finalStatus = tapStatus
            }
        }

        return finalStatus
    }

    private static func render(
        inputData: UnsafePointer<AudioBufferList>,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        state: RenderState
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let outputs = UnsafeMutableAudioBufferListPointer(outputData)
        let gain = state.gain

        for index in outputs.indices {
            guard let outputPointer = outputs[index].mData else { continue }

            guard index < inputs.count,
                  let inputPointer = inputs[index].mData else {
                memset(outputPointer, 0, Int(outputs[index].mDataByteSize))
                continue
            }

            let byteCount = min(Int(inputs[index].mDataByteSize), Int(outputs[index].mDataByteSize))
            if gain <= 0 {
                memset(outputPointer, 0, byteCount)
            } else if abs(gain - 1) < 0.0001 {
                memcpy(outputPointer, inputPointer, byteCount)
            } else {
                let sampleCount = byteCount / MemoryLayout<Float32>.stride
                let inputSamples = inputPointer.assumingMemoryBound(to: Float32.self)
                let outputSamples = outputPointer.assumingMemoryBound(to: Float32.self)
                for sampleIndex in 0..<sampleCount {
                    outputSamples[sampleIndex] = inputSamples[sampleIndex] * gain
                }
            }

            outputs[index].mDataByteSize = UInt32(byteCount)
        }
    }

    private func audioError(_ format: String, _ status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [
                NSLocalizedDescriptionKey: String(
                    format: String(localized: String.LocalizationValue(format)),
                    Int(status)
                )
            ]
        )
    }

    private static func statusCode(from error: Error) -> OSStatus? {
        let nsError = error as NSError
        guard nsError.domain == NSOSStatusErrorDomain else { return nil }
        return OSStatus(nsError.code)
    }
}
