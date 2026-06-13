import Foundation

final class AudioEqualizerProcessor {
    private struct Band {
        var b0: Float
        var b1: Float
        var b2: Float
        var a1: Float
        var a2: Float
        var x1L: Float = 0
        var x2L: Float = 0
        var y1L: Float = 0
        var y2L: Float = 0
        var x1R: Float = 0
        var x2R: Float = 0
        var y1R: Float = 0
        var y2R: Float = 0

        mutating func process(left: Float, right: Float) -> (left: Float, right: Float) {
            let outLeft = b0 * left + b1 * x1L + b2 * x2L - a1 * y1L - a2 * y2L
            x2L = x1L
            x1L = left
            y2L = y1L
            y1L = outLeft

            let outRight = b0 * right + b1 * x1R + b2 * x2R - a1 * y1R - a2 * y2R
            x2R = x1R
            x1R = right
            y2R = y1R
            y1R = outRight

            guard outLeft.isFinite, outRight.isFinite else {
                reset()
                return (0, 0)
            }

            return (outLeft, outRight)
        }

        mutating func reset() {
            x1L = 0
            x2L = 0
            y1L = 0
            y2L = 0
            x1R = 0
            x2R = 0
            y1R = 0
            y2R = 0
        }

        static let unity = Band(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)
    }

    private var bands: [Band] = Array(repeating: .unity, count: AudioEqualizerSettings.bandCount)
    private var isEnabled = false
    private var sampleRate: Double

    init(sampleRate: Double, settings: AudioEqualizerSettings = .flat) {
        self.sampleRate = sampleRate
        update(settings: settings, sampleRate: sampleRate)
    }

    func update(settings: AudioEqualizerSettings, sampleRate: Double? = nil) {
        if let sampleRate, sampleRate > 0 {
            self.sampleRate = sampleRate
        }

        let gains = settings.clampedBandGains
        isEnabled = settings.isEnabled && gains.contains { abs($0) > 0.001 }
        bands = zip(AudioEqualizerSettings.frequencies, gains).map { frequency, gain in
            guard isEnabled, frequency > 0, frequency < self.sampleRate / 2 else {
                return .unity
            }
            return Self.peakingBand(
                frequency: frequency,
                gainDB: gain,
                q: 1.4,
                sampleRate: self.sampleRate
            )
        }
    }

    func processInterleavedStereo(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard isEnabled, frameCount > 0 else { return }

        for bandIndex in bands.indices {
            for frame in 0..<frameCount {
                let base = frame * 2
                let processed = bands[bandIndex].process(
                    left: samples[base],
                    right: samples[base + 1]
                )
                samples[base] = processed.left
                samples[base + 1] = processed.right
            }
        }
    }

    static func peakingCoefficients(
        frequency: Double,
        gainDB: Double,
        q: Double,
        sampleRate: Double
    ) -> [Double] {
        let amplitude = pow(10.0, gainDB / 40.0)
        let omega = 2.0 * .pi * frequency / sampleRate
        let sinOmega = sin(omega)
        let cosOmega = cos(omega)
        let alpha = sinOmega / (2.0 * q)

        let b0 = 1.0 + alpha * amplitude
        let b1 = -2.0 * cosOmega
        let b2 = 1.0 - alpha * amplitude
        let a0 = 1.0 + alpha / amplitude
        let a1 = -2.0 * cosOmega
        let a2 = 1.0 - alpha / amplitude

        return [
            b0 / a0,
            b1 / a0,
            b2 / a0,
            a1 / a0,
            a2 / a0
        ]
    }

    private static func peakingBand(
        frequency: Double,
        gainDB: Double,
        q: Double,
        sampleRate: Double
    ) -> Band {
        let coefficients = peakingCoefficients(
            frequency: frequency,
            gainDB: gainDB,
            q: q,
            sampleRate: sampleRate
        )
        return Band(
            b0: Float(coefficients[0]),
            b1: Float(coefficients[1]),
            b2: Float(coefficients[2]),
            a1: Float(coefficients[3]),
            a2: Float(coefficients[4])
        )
    }
}
