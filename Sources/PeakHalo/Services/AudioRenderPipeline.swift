import AudioToolbox
import Foundation

final class AudioRenderState {
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

enum AudioRenderPipeline {
    static func render(
        inputData: UnsafePointer<AudioBufferList>,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        state: AudioRenderState
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

    static func rampCoefficient(sampleRate: Double, rampTimeSeconds: Double = 0.030) -> Float {
        let safeSampleRate = max(1, sampleRate)
        let safeRampTime = max(0.001, rampTimeSeconds)
        return Float(1 - exp(-1 / (safeSampleRate * safeRampTime)))
    }

    private static func renderMappedBuffers(
        inputBuffers: UnsafeMutableAudioBufferListPointer,
        outputBuffers: UnsafeMutableAudioBufferListPointer,
        gainProvider: () -> Float,
        equalizer: AudioRenderState?,
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
}
