import Accelerate

enum AudioSoftLimiter {
    static let threshold: Float = 0.95
    static let ceiling: Float = 1.0

    private static var headroom: Float {
        ceiling - threshold
    }

    @inline(__always)
    static func apply(_ sample: Float) -> Float {
        let magnitude = abs(sample)
        guard magnitude > threshold else { return sample }

        let overshoot = magnitude - threshold
        let compressed = threshold + headroom * (overshoot / (overshoot + headroom))
        return sample >= 0 ? compressed : -compressed
    }

    @inline(__always)
    static func processBuffer(_ buffer: UnsafeMutablePointer<Float>, sampleCount: Int) {
        guard sampleCount > 0 else { return }

        var peak: Float = 0
        vDSP_maxmgv(buffer, 1, &peak, vDSP_Length(sampleCount))
        guard peak > threshold else { return }

        for index in 0..<sampleCount {
            buffer[index] = apply(buffer[index])
        }
    }
}
