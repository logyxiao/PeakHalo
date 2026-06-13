import AudioToolbox
import Testing
@testable import PeakHalo

private final class TestAudioBufferList {
    let pointer: UnsafeMutablePointer<AudioBufferList>
    private var dataPointers: [UnsafeMutablePointer<Float>] = []
    private var dataSampleCounts: [Int] = []

    init(buffers: [(channels: UInt32, frames: Int)]) {
        precondition(!buffers.isEmpty, "Must have at least one buffer.")

        let extraBuffers = max(0, buffers.count - 1)
        let byteCount = MemoryLayout<AudioBufferList>.size
            + extraBuffers * MemoryLayout<AudioBuffer>.stride
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        pointer = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        pointer.pointee.mNumberBuffers = UInt32(buffers.count)

        let bufferList = UnsafeMutableAudioBufferListPointer(pointer)
        for index in buffers.indices {
            let channels = buffers[index].channels
            let frames = buffers[index].frames
            let sampleCount = Int(channels) * frames
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: max(sampleCount, 1))
            samples.initialize(repeating: 0, count: max(sampleCount, 1))
            dataPointers.append(samples)
            dataSampleCounts.append(max(sampleCount, 1))

            bufferList[index] = AudioBuffer(
                mNumberChannels: channels,
                mDataByteSize: UInt32(sampleCount * MemoryLayout<Float>.stride),
                mData: UnsafeMutableRawPointer(samples)
            )
        }
    }

    deinit {
        for (index, pointer) in dataPointers.enumerated() {
            pointer.deinitialize(count: dataSampleCounts[index])
            pointer.deallocate()
        }
        pointer.deallocate()
    }

    var bufferList: UnsafeMutableAudioBufferListPointer {
        UnsafeMutableAudioBufferListPointer(pointer)
    }

    func data(at index: Int) -> UnsafeMutablePointer<Float> {
        dataPointers[index]
    }

    func sampleCount(at index: Int) -> Int {
        Int(bufferList[index].mDataByteSize) / MemoryLayout<Float>.stride
    }
}

private func fill(_ bufferList: TestAudioBufferList, index: Int, value: Float) {
    let data = bufferList.data(at: index)
    for sampleIndex in 0..<bufferList.sampleCount(at: index) {
        data[sampleIndex] = value
    }
}

private func render(
    input: TestAudioBufferList,
    output: TestAudioBufferList,
    gain: Float = 1,
    preferredStereoLeft: Int = 0,
    preferredStereoRight: Int = 1
) {
    AudioProcessTapService.renderMappedBuffers(
        inputBuffers: input.bufferList,
        outputBuffers: output.bufferList,
        gain: gain,
        preferredStereoLeft: preferredStereoLeft,
        preferredStereoRight: preferredStereoRight
    )
}

@Suite("Audio process tap render mapping")
struct AudioProcessTapRenderTests {
    @Test("Stereo 2ch to 2ch passes through with gain")
    func stereoPassThrough() {
        let input = TestAudioBufferList(buffers: [(channels: 2, frames: 8)])
        let output = TestAudioBufferList(buffers: [(channels: 2, frames: 8)])
        let inputData = input.data(at: 0)
        for frame in 0..<8 {
            inputData[frame * 2] = 0.5
            inputData[frame * 2 + 1] = 0.25
        }

        render(input: input, output: output, gain: 0.5)

        let outputData = output.data(at: 0)
        for frame in 0..<8 {
            #expect(outputData[frame * 2] == 0.25)
            #expect(outputData[frame * 2 + 1] == 0.125)
        }
    }

    @Test("Boosted render output is soft-limited")
    func boostedRenderOutputIsSoftLimited() {
        let input = TestAudioBufferList(buffers: [(channels: 2, frames: 4)])
        let output = TestAudioBufferList(buffers: [(channels: 2, frames: 4)])
        fill(input, index: 0, value: 0.9)

        render(input: input, output: output, gain: 2)

        let outputData = output.data(at: 0)
        for sampleIndex in 0..<output.sampleCount(at: 0) {
            #expect(outputData[sampleIndex] > AudioSoftLimiter.threshold)
            #expect(outputData[sampleIndex] < AudioSoftLimiter.ceiling)
        }
    }

    @Test("More input buffers than output buffers maps from the end")
    func mapsFromInputTail() {
        let input = TestAudioBufferList(buffers: [
            (channels: 2, frames: 4),
            (channels: 2, frames: 4)
        ])
        let output = TestAudioBufferList(buffers: [(channels: 2, frames: 4)])
        fill(input, index: 0, value: 0)
        fill(input, index: 1, value: 0.42)

        render(input: input, output: output)

        let outputData = output.data(at: 0)
        for sampleIndex in 0..<output.sampleCount(at: 0) {
            #expect(outputData[sampleIndex] == 0.42)
        }
    }

    @Test("Stereo input to 6ch output writes preferred stereo channels only")
    func stereoToSurroundPreferredChannels() {
        let input = TestAudioBufferList(buffers: [(channels: 2, frames: 4)])
        let output = TestAudioBufferList(buffers: [(channels: 6, frames: 4)])
        let inputData = input.data(at: 0)
        for frame in 0..<4 {
            inputData[frame * 2] = 0.5
            inputData[frame * 2 + 1] = 0.3
        }

        render(input: input, output: output, preferredStereoLeft: 2, preferredStereoRight: 3)

        let outputData = output.data(at: 0)
        for frame in 0..<4 {
            let base = frame * 6
            #expect(outputData[base + 0] == 0)
            #expect(outputData[base + 1] == 0)
            #expect(outputData[base + 2] == 0.5)
            #expect(outputData[base + 3] == 0.3)
            #expect(outputData[base + 4] == 0)
            #expect(outputData[base + 5] == 0)
        }
    }

    @Test("Mono input copies to preferred left and right channels")
    func monoCopiesToPreferredStereoPair() {
        let input = TestAudioBufferList(buffers: [(channels: 1, frames: 4)])
        let output = TestAudioBufferList(buffers: [(channels: 4, frames: 4)])
        fill(input, index: 0, value: 0.8)

        render(input: input, output: output, preferredStereoLeft: 1, preferredStereoRight: 2)

        let outputData = output.data(at: 0)
        for frame in 0..<4 {
            let base = frame * 4
            #expect(outputData[base + 0] == 0)
            #expect(outputData[base + 1] == 0.8)
            #expect(outputData[base + 2] == 0.8)
            #expect(outputData[base + 3] == 0)
        }
    }
}
