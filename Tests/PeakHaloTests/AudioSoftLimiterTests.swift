import Testing
@testable import PeakHalo

@Suite("Audio soft limiter")
struct AudioSoftLimiterTests {
    @Test("Samples below threshold pass through unchanged")
    func belowThresholdPassesThrough() {
        #expect(AudioSoftLimiter.apply(0.25) == 0.25)
        #expect(AudioSoftLimiter.apply(-0.95) == -0.95)
    }

    @Test("Samples above threshold compress toward ceiling")
    func aboveThresholdCompressesTowardCeiling() {
        let positive = AudioSoftLimiter.apply(1.6)
        let negative = AudioSoftLimiter.apply(-1.6)

        #expect(positive > AudioSoftLimiter.threshold)
        #expect(positive < AudioSoftLimiter.ceiling)
        #expect(negative < -AudioSoftLimiter.threshold)
        #expect(negative > -AudioSoftLimiter.ceiling)
        #expect(abs(positive + negative) < 0.000_001)
    }

    @Test("Buffer processing limits boosted peaks")
    func bufferProcessingLimitsBoostedPeaks() {
        var samples: [Float] = [0.2, 1.4, -1.5, 0.7]

        samples.withUnsafeMutableBufferPointer { buffer in
            AudioSoftLimiter.processBuffer(buffer.baseAddress!, sampleCount: buffer.count)
        }

        #expect(samples[0] == 0.2)
        #expect(samples[1] < 1.0)
        #expect(samples[2] > -1.0)
        #expect(samples[3] == 0.7)
    }
}
