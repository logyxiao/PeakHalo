import AudioToolbox
import CoreAudio
import CoreFoundation
import Foundation
import os

final class AudioProcessTapService {
    private final class RenderState {
        private var targetGain: Float
        private var currentGain: Float
        private let rampCoefficient: Float
        private let equalizer: AudioEqualizerProcessor
        var isMuted: Bool
        let preferredStereoLeft: Int
        let preferredStereoRight: Int

        init(
            volume: Double,
            isMuted: Bool,
            boost: AudioBoostLevel,
            deviceGain: Double,
            rampCoefficient: Float,
            equalizer: AudioEqualizerSettings,
            sampleRate: Double,
            preferredStereoLeft: Int,
            preferredStereoRight: Int
        ) {
            let gain = Self.gain(volume: volume, isMuted: isMuted, boost: boost, deviceGain: deviceGain)
            self.targetGain = gain
            self.currentGain = gain
            self.rampCoefficient = rampCoefficient
            self.equalizer = AudioEqualizerProcessor(sampleRate: sampleRate, settings: equalizer)
            self.isMuted = isMuted
            self.preferredStereoLeft = preferredStereoLeft
            self.preferredStereoRight = preferredStereoRight
        }

        func update(
            volume: Double,
            isMuted: Bool,
            boost: AudioBoostLevel,
            deviceGain: Double,
            equalizer: AudioEqualizerSettings
        ) {
            self.targetGain = Self.gain(volume: volume, isMuted: isMuted, boost: boost, deviceGain: deviceGain)
            self.equalizer.update(settings: equalizer)
            self.isMuted = isMuted
        }

        func nextGain() -> Float {
            let delta = targetGain - currentGain
            guard abs(delta) > 0.000_001 else {
                currentGain = targetGain
                return targetGain
            }

            currentGain += delta * rampCoefficient
            return currentGain
        }

        func processEqualizerIfNeeded(_ samples: UnsafeMutablePointer<Float>, frameCount: Int, channelCount: Int) {
            guard channelCount == 2 else { return }
            equalizer.processInterleavedStereo(samples, frameCount: frameCount)
        }

        private static func gain(
            volume: Double,
            isMuted: Bool,
            boost: AudioBoostLevel,
            deviceGain: Double
        ) -> Float {
            guard !isMuted else { return 0 }
            let clampedVolume = min(100, max(0, volume))
            let clampedDeviceGain = min(1, max(0, deviceGain))
            return Float((clampedVolume / 100) * boost.rawValue * clampedDeviceGain)
        }
    }

    private struct ActiveTap {
        let itemID: String
        let processObjectIDs: [AudioObjectID]
        let route: AudioProcessTapRoute
        let tapSourceDeviceUID: String?
        let tapID: AudioObjectID
        let aggregateDeviceID: AudioObjectID
        let deviceProcID: AudioDeviceIOProcID
        let description: CATapDescription
        let renderState: RenderState
    }

    private let queue = DispatchQueue(label: "peakhalo.audio-process-tap", qos: .userInitiated)
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PeakHalo",
        category: "AudioProcessTapService"
    )
    private var activeTaps: [String: ActiveTap] = [:]

    deinit {
        deactivateAll()
    }

    func activate(
        itemID: String,
        processObjectIDs: [AudioObjectID],
        route: AudioProcessTapRoute?,
        volume: Double,
        isMuted: Bool,
        boost: AudioBoostLevel,
        deviceGain: Double = 1,
        equalizer: AudioEqualizerSettings = .flat,
        completion: @escaping (AudioProcessTapResult) -> Void
    ) {
        switchOutputDevice(
            itemID: itemID,
            processObjectIDs: processObjectIDs,
            route: route,
            volume: volume,
            isMuted: isMuted,
            boost: boost,
            deviceGain: deviceGain,
            equalizer: equalizer,
            completion: completion
        )
    }

    func switchOutputDevice(
        itemID: String,
        processObjectIDs: [AudioObjectID],
        route: AudioProcessTapRoute?,
        volume: Double,
        isMuted: Bool,
        boost: AudioBoostLevel,
        deviceGain: Double = 1,
        equalizer: AudioEqualizerSettings = .flat,
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

            guard let route else {
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
                if activeTap.route == route,
                   activeTap.processObjectIDs == processObjectIDs {
                    activeTap.renderState.update(
                        volume: volume,
                        isMuted: isMuted,
                        boost: boost,
                        deviceGain: deviceGain,
                        equalizer: equalizer
                    )
                    completion(AudioProcessTapResult(itemID: itemID, success: true, message: nil))
                    return
                }

                self.switchActiveTap(
                    activeTap,
                    processObjectIDs: processObjectIDs,
                    route: route,
                    volume: volume,
                    isMuted: isMuted,
                    boost: boost,
                    deviceGain: deviceGain,
                    equalizer: equalizer,
                    completion: completion
                )
                return
            }

            do {
                let activeTap = try self.createActiveTap(
                    itemID: itemID,
                    processObjectIDs: processObjectIDs,
                    route: route,
                    volume: volume,
                    isMuted: isMuted,
                    boost: boost,
                    deviceGain: deviceGain,
                    equalizer: equalizer
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
        boost: AudioBoostLevel,
        deviceGain: Double = 1,
        equalizer: AudioEqualizerSettings = .flat
    ) {
        queue.async {
            self.activeTaps[itemID]?.renderState.update(
                volume: volume,
                isMuted: isMuted,
                boost: boost,
                deviceGain: deviceGain,
                equalizer: equalizer
            )
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
        route: AudioProcessTapRoute,
        volume: Double,
        isMuted: Bool,
        boost: AudioBoostLevel,
        deviceGain: Double,
        equalizer: AudioEqualizerSettings
    ) throws -> ActiveTap {
        let tap = try createProcessTap(processObjectIDs: processObjectIDs, route: route)
        let outputDevices = route.resolvedOutputDevices
        let outputDeviceUIDs = outputDevices.map(\.uid)
        guard let mainOutputDevice = outputDevices.first else {
            AudioHardwareDestroyProcessTap(tap.id)
            throw NSError(
                domain: "AudioProcessTapService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "No output device is available for audio processing.")]
            )
        }
        let outputDescription = outputDeviceUIDs.joined(separator: ",")

        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        let aggregateDescription = aggregateDeviceDescription(
            outputDeviceUIDs: outputDeviceUIDs,
            tapUUID: tap.description.uuid,
            itemID: itemID
        )
        var status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != AudioObjectID(kAudioObjectUnknown) else {
            AudioHardwareDestroyProcessTap(tap.id)
            logger.error("Could not create aggregate device for \(outputDescription, privacy: .public): \(status, privacy: .public)")
            throw audioError("Could not create aggregate device (%d).", status)
        }

        guard waitUntilReady(aggregateID, timeout: 2.0) else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tap.id)
            logger.error("Aggregate device was not ready for \(outputDescription, privacy: .public)")
            throw NSError(
                domain: "AudioProcessTapService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Aggregate device was not ready for audio processing.")]
            )
        }

        let preferred = preferredStereoChannels(deviceID: mainOutputDevice.id)
        let sampleRate = nominalSampleRate(deviceID: aggregateID)
            ?? nominalSampleRate(deviceID: mainOutputDevice.id)
            ?? 48_000
        let rampCoefficient = Self.rampCoefficient(sampleRate: sampleRate)
        let renderState = RenderState(
            volume: volume,
            isMuted: isMuted,
            boost: boost,
            deviceGain: deviceGain,
            rampCoefficient: rampCoefficient,
            equalizer: equalizer,
            sampleRate: sampleRate,
            preferredStereoLeft: preferred.left,
            preferredStereoRight: preferred.right
        )
        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inputData, _, outputData, _ in
            Self.render(inputData: inputData, outputData: outputData, state: renderState)
        }
        guard status == noErr, let procID else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tap.id)
            logger.error("Could not create IOProc for \(outputDescription, privacy: .public): \(status, privacy: .public)")
            throw audioError("Could not create audio processing callback (%d).", status)
        }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tap.id)
            logger.error("Could not start aggregate device for \(outputDescription, privacy: .public): \(status, privacy: .public)")
            throw audioError("Could not start audio processing (%d).", status)
        }

        logger.info(
            "Activated tap item=\(itemID, privacy: .public) outputs=\(outputDescription, privacy: .public) source=\(tap.sourceDeviceUID ?? "mixdown", privacy: .public)"
        )

        return ActiveTap(
            itemID: itemID,
            processObjectIDs: processObjectIDs,
            route: route,
            tapSourceDeviceUID: tap.sourceDeviceUID,
            tapID: tap.id,
            aggregateDeviceID: aggregateID,
            deviceProcID: procID,
            description: tap.description,
            renderState: renderState
        )
    }

    @available(macOS 14.2, *)
    private func createProcessTap(
        processObjectIDs: [AudioObjectID],
        route: AudioProcessTapRoute
    ) throws -> (description: CATapDescription, id: AudioObjectID, sourceDeviceUID: String?) {
        var streamTapStatus = noErr

        if let sourceDeviceUID = route.preferredTapSourceDeviceUID {
            if let stream = outputStreamIndex(for: sourceDeviceUID) {
                let streamTap = CATapDescription(
                    processes: processObjectIDs,
                    deviceUID: sourceDeviceUID,
                    stream: stream
                )
                streamTap.uuid = UUID()
                streamTap.isPrivate = true
                streamTap.muteBehavior = .mutedWhenTapped

                var tapID = AudioObjectID(kAudioObjectUnknown)
                streamTapStatus = AudioHardwareCreateProcessTap(streamTap, &tapID)
                if streamTapStatus == noErr, tapID != AudioObjectID(kAudioObjectUnknown) {
                    logger.info("Created stream-specific tap source=\(sourceDeviceUID, privacy: .public) stream=\(stream, privacy: .public)")
                    return (streamTap, tapID, sourceDeviceUID)
                }

                logger.warning(
                    "Stream-specific tap failed source=\(sourceDeviceUID, privacy: .public) status=\(streamTapStatus, privacy: .public); using mixdown"
                )
            } else {
                logger.warning("Could not resolve output stream source=\(sourceDeviceUID, privacy: .public); using mixdown")
            }
        }

        let mixdownTap = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        mixdownTap.uuid = UUID()
        mixdownTap.isPrivate = true
        mixdownTap.muteBehavior = .mutedWhenTapped

        var mixdownTapID = AudioObjectID(kAudioObjectUnknown)
        let mixdownStatus = AudioHardwareCreateProcessTap(mixdownTap, &mixdownTapID)
        guard mixdownStatus == noErr, mixdownTapID != AudioObjectID(kAudioObjectUnknown) else {
            logger.error(
                "Could not create process tap streamStatus=\(streamTapStatus, privacy: .public) mixdownStatus=\(mixdownStatus, privacy: .public)"
            )
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(mixdownStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        format: String(localized: "Could not create process tap (stream %d, mixdown %d)."),
                        Int(streamTapStatus),
                        Int(mixdownStatus)
                    )
                ]
            )
        }

        logger.info("Created mixdown tap output=\(route.outputDeviceUID, privacy: .public)")
        return (mixdownTap, mixdownTapID, nil)
    }

    @available(macOS 14.2, *)
    private func switchActiveTap(
        _ activeTap: ActiveTap,
        processObjectIDs: [AudioObjectID],
        route: AudioProcessTapRoute,
        volume: Double,
        isMuted: Bool,
        boost: AudioBoostLevel,
        deviceGain: Double,
        equalizer: AudioEqualizerSettings,
        completion: @escaping (AudioProcessTapResult) -> Void
    ) {
        do {
            let nextTap = try createActiveTap(
                itemID: activeTap.itemID,
                processObjectIDs: processObjectIDs,
                route: route,
                volume: volume,
                isMuted: isMuted,
                boost: boost,
                deviceGain: deviceGain,
                equalizer: equalizer
            )
            activeTaps[activeTap.itemID] = nextTap

            let destroyStatus = destroy(activeTap)
            if destroyStatus != noErr {
                logger.error("Old tap cleanup failed item=\(activeTap.itemID, privacy: .public) status=\(destroyStatus, privacy: .public)")
            }

            completion(AudioProcessTapResult(itemID: activeTap.itemID, success: true, message: nil))
        } catch {
            let statusCode = Self.statusCode(from: error)
            completion(AudioProcessTapResult(
                itemID: activeTap.itemID,
                success: false,
                message: error.localizedDescription,
                statusCode: statusCode
            ))
        }
    }

    private func aggregateDeviceDescription(
        outputDeviceUIDs: [String],
        tapUUID: UUID,
        itemID: String
    ) -> [String: Any] {
        let mainOutputDeviceUID = outputDeviceUIDs[0]
        let subdevices = outputDeviceUIDs.enumerated().map { index, uid in
            [
                kAudioSubDeviceUIDKey: uid,
                kAudioSubDeviceDriftCompensationKey: index == 0 ? false : true
            ] as [String: Any]
        }

        return [
            kAudioAggregateDeviceNameKey: "PeakHalo-\(itemID)",
            kAudioAggregateDeviceUIDKey: "com.logyxiao.PeakHalo.audio.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: mainOutputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: mainOutputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: subdevices,
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
        renderMappedBuffers(
            inputBuffers: inputs,
            outputBuffers: outputs,
            gainProvider: { state.nextGain() },
            equalizer: state,
            preferredStereoLeft: state.preferredStereoLeft,
            preferredStereoRight: state.preferredStereoRight
        )
    }

    static func renderMappedBuffers(
        inputBuffers: UnsafeMutableAudioBufferListPointer,
        outputBuffers: UnsafeMutableAudioBufferListPointer,
        gain: Float,
        preferredStereoLeft: Int,
        preferredStereoRight: Int
    ) {
        renderMappedBuffers(
            inputBuffers: inputBuffers,
            outputBuffers: outputBuffers,
            gainProvider: { gain },
            equalizer: nil,
            preferredStereoLeft: preferredStereoLeft,
            preferredStereoRight: preferredStereoRight
        )
    }

    private static func renderMappedBuffers(
        inputBuffers: UnsafeMutableAudioBufferListPointer,
        outputBuffers: UnsafeMutableAudioBufferListPointer,
        gainProvider: () -> Float,
        equalizer: RenderState?,
        preferredStereoLeft: Int,
        preferredStereoRight: Int
    ) {
        let inputBufferCount = inputBuffers.count
        let outputBufferCount = outputBuffers.count

        for outputIndex in 0..<outputBufferCount {
            let outputBuffer = outputBuffers[outputIndex]
            guard let outputData = outputBuffer.mData else { continue }

            let inputIndex: Int
            if inputBufferCount > outputBufferCount {
                inputIndex = inputBufferCount - outputBufferCount + outputIndex
            } else {
                inputIndex = outputIndex
            }

            guard inputIndex < inputBufferCount else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let inputBuffer = inputBuffers[inputIndex]
            guard let inputData = inputBuffer.mData else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let inputSamples = inputData.assumingMemoryBound(to: Float.self)
            let outputSamples = outputData.assumingMemoryBound(to: Float.self)
            let inputChannels = max(1, Int(inputBuffer.mNumberChannels))
            let outputChannels = max(1, Int(outputBuffer.mNumberChannels))
            let inputSampleCount = Int(inputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let outputSampleCount = Int(outputBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let inputFrameCount = inputSampleCount / inputChannels
            let outputFrameCount = outputSampleCount / outputChannels
            let frameCount = min(inputFrameCount, outputFrameCount)

            guard frameCount > 0 else {
                memset(outputData, 0, Int(outputBuffer.mDataByteSize))
                continue
            }

            let safeLeft = min(max(preferredStereoLeft, 0), max(outputChannels - 1, 0))
            let safeRight = min(max(preferredStereoRight, 0), max(outputChannels - 1, 0))

            if inputChannels == outputChannels {
                for frame in 0..<frameCount {
                    let gain = gainProvider()
                    let base = frame * inputChannels
                    for channel in 0..<inputChannels {
                        outputSamples[base + channel] = gain > 0
                            ? inputSamples[base + channel] * gain
                            : 0
                    }
                }
                let writtenSamples = frameCount * inputChannels
                if writtenSamples < outputSampleCount {
                    memset(
                        outputSamples.advanced(by: writtenSamples),
                        0,
                        (outputSampleCount - writtenSamples) * MemoryLayout<Float>.size
                    )
                }
            } else if inputChannels == 2 && outputChannels > 2 {
                for frame in 0..<frameCount {
                    let gain = gainProvider()
                    let inBase = frame * 2
                    let outBase = frame * outputChannels
                    for channel in 0..<outputChannels {
                        outputSamples[outBase + channel] = 0
                    }
                    if gain > 0 {
                        outputSamples[outBase + safeLeft] = inputSamples[inBase] * gain
                        outputSamples[outBase + safeRight] = inputSamples[inBase + 1] * gain
                    }
                }
                zeroRemainingOutputSamples(
                    outputSamples: outputSamples,
                    writtenSamples: frameCount * outputChannels,
                    outputSampleCount: outputSampleCount
                )
            } else if inputChannels == 1 && outputChannels > 1 {
                for frame in 0..<frameCount {
                    let gain = gainProvider()
                    let outBase = frame * outputChannels
                    let sample = inputSamples[frame] * gain
                    for channel in 0..<outputChannels {
                        outputSamples[outBase + channel] = 0
                    }
                    if gain > 0 {
                        outputSamples[outBase + safeLeft] = sample
                        outputSamples[outBase + safeRight] = sample
                    }
                }
                zeroRemainingOutputSamples(
                    outputSamples: outputSamples,
                    writtenSamples: frameCount * outputChannels,
                    outputSampleCount: outputSampleCount
                )
            } else {
                for frame in 0..<frameCount {
                    let gain = gainProvider()
                    let inBase = frame * inputChannels
                    let outBase = frame * outputChannels
                    let copiedChannels = min(inputChannels, outputChannels)

                    for channel in 0..<copiedChannels {
                        outputSamples[outBase + channel] = gain > 0
                            ? inputSamples[inBase + channel] * gain
                            : 0
                    }
                    if copiedChannels < outputChannels {
                        for channel in copiedChannels..<outputChannels {
                            outputSamples[outBase + channel] = 0
                        }
                    }
                }
                zeroRemainingOutputSamples(
                    outputSamples: outputSamples,
                    writtenSamples: frameCount * outputChannels,
                    outputSampleCount: outputSampleCount
                )
            }

            equalizer?.processEqualizerIfNeeded(
                outputSamples,
                frameCount: frameCount,
                channelCount: outputChannels
            )
            AudioSoftLimiter.processBuffer(
                outputSamples,
                sampleCount: frameCount * outputChannels
            )
        }
    }

    private static func zeroRemainingOutputSamples(
        outputSamples: UnsafeMutablePointer<Float>,
        writtenSamples: Int,
        outputSampleCount: Int
    ) {
        guard writtenSamples < outputSampleCount else { return }
        memset(
            outputSamples.advanced(by: writtenSamples),
            0,
            (outputSampleCount - writtenSamples) * MemoryLayout<Float>.size
        )
    }

    private func preferredStereoChannels(deviceID: AudioObjectID) -> (left: Int, right: Int) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var channels: [UInt32] = [1, 2]
        var size = UInt32(MemoryLayout<UInt32>.size * channels.count)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &channels)
        guard status == noErr, channels.count >= 2 else {
            return (0, 1)
        }

        return (max(0, Int(channels[0]) - 1), max(0, Int(channels[1]) - 1))
    }

    private func nominalSampleRate(deviceID: AudioObjectID) -> Double? {
        var sampleRate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &sampleRate)
        guard status == noErr, sampleRate > 0 else { return nil }
        return sampleRate
    }

    private static func rampCoefficient(sampleRate: Double, rampTimeSeconds: Double = 0.030) -> Float {
        let safeSampleRate = max(1, sampleRate)
        let safeRampTime = max(0.001, rampTimeSeconds)
        return Float(1 - exp(-1 / (safeSampleRate * safeRampTime)))
    }

    private func outputStreamIndex(for deviceUID: String) -> UInt? {
        guard let deviceID = audioDeviceID(for: deviceUID) else { return nil }

        if let globalStreams = streamIDs(deviceID: deviceID, scope: kAudioObjectPropertyScopeGlobal) {
            for (index, streamID) in globalStreams.enumerated() {
                if uint32Property(
                    objectID: streamID,
                    selector: kAudioStreamPropertyDirection,
                    scope: kAudioObjectPropertyScopeGlobal
                ) == 0 {
                    return UInt(index)
                }
            }
        }

        if let outputStreams = streamIDs(deviceID: deviceID, scope: kAudioObjectPropertyScopeOutput),
           !outputStreams.isEmpty {
            return 0
        }

        return nil
    }

    private func streamIDs(
        deviceID: AudioObjectID,
        scope: AudioObjectPropertyScope
    ) -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0 else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var streams = [AudioObjectID](repeating: 0, count: count)
        let status = streams.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer.baseAddress!)
        }
        guard status == noErr else { return nil }
        return streams
    }

    private func audioDeviceID(for uid: String) -> AudioObjectID? {
        for deviceID in audioDevices() {
            if stringProperty(objectID: deviceID, selector: kAudioDevicePropertyDeviceUID) == uid {
                return deviceID
            }
        }

        return nil
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
        let status = devices.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                buffer.baseAddress!
            )
        }
        guard status == noErr else { return [] }
        return devices
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                UnsafeMutableRawPointer(pointer)
            )
        }
        guard status == noErr, let unmanaged else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    private func uint32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    private func waitUntilReady(
        _ deviceID: AudioObjectID,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.01
    ) -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            if isDeviceAlive(deviceID) {
                return true
            }
            CFRunLoopRunInMode(.defaultMode, pollInterval, false)
        }

        return false
    }

    private func isDeviceAlive(_ deviceID: AudioObjectID) -> Bool {
        uint32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceIsAlive,
            scope: kAudioObjectPropertyScopeGlobal
        ) != 0
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
