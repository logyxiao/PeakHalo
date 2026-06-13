import Testing
@testable import PeakHalo

@Suite("Audio equalizer")
struct AudioEqualizerTests {
    @Test("Settings normalize to ten clamped bands")
    func settingsNormalizeToTenClampedBands() {
        let settings = AudioEqualizerSettings(
            bandGains: [-20, -12, -6, 0, 6, 12, 20],
            isEnabled: true
        )

        #expect(settings.bandGains.count == AudioEqualizerSettings.bandCount)
        #expect(settings.bandGains[0] == AudioEqualizerSettings.minGainDB)
        #expect(settings.bandGains[5] == AudioEqualizerSettings.maxGainDB)
        #expect(settings.bandGains[6] == AudioEqualizerSettings.maxGainDB)
        #expect(settings.bandGains[7] == 0)
    }

    @Test("Preset settings enable non-flat curves")
    func presetSettingsEnableNonFlatCurves() {
        #expect(!AudioEqualizerPreset.flat.settings.isEnabled)
        #expect(AudioEqualizerPreset.bassBoost.settings.isEnabled)
        #expect(AudioEqualizerPreset.bassBoost.settings.bandGains.count == AudioEqualizerSettings.bandCount)
    }

    @Test("Flat equalizer leaves stereo buffer unchanged")
    func flatEqualizerBypassesBuffer() {
        let processor = AudioEqualizerProcessor(sampleRate: 48_000, settings: .flat)
        var samples: [Float] = [0.1, -0.2, 0.3, -0.4, 0.5, -0.6]
        let original = samples

        samples.withUnsafeMutableBufferPointer { buffer in
            processor.processInterleavedStereo(buffer.baseAddress!, frameCount: buffer.count / 2)
        }

        #expect(samples == original)
    }

    @Test("Enabled equalizer produces finite processed samples")
    func enabledEqualizerProducesFiniteSamples() {
        let processor = AudioEqualizerProcessor(
            sampleRate: 48_000,
            settings: AudioEqualizerSettings(
                bandGains: [6, 4, 2, 0, -2, -2, 0, 2, 4, 6],
                isEnabled: true
            )
        )
        var samples: [Float] = [1, 1] + Array(repeating: 0, count: 30)

        samples.withUnsafeMutableBufferPointer { buffer in
            processor.processInterleavedStereo(buffer.baseAddress!, frameCount: buffer.count / 2)
        }

        #expect(samples.allSatisfy { $0.isFinite })
        #expect(samples != [1, 1] + Array(repeating: 0, count: 30))
    }
}
