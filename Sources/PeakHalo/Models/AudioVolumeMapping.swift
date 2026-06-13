import Foundation

enum AudioVolumeMapping {
    static func sliderPercent(forGainPercent gainPercent: Double, backend: AudioOutputVolumeBackend) -> Double {
        switch backend {
        case .software:
            guard gainPercent > 0 else { return 0 }
            return sqrt(min(100, gainPercent) / 100) * 100
        case .hardware, .display, .unavailable:
            return clampPercent(gainPercent)
        }
    }

    static func gainPercent(forSliderPercent sliderPercent: Double, backend: AudioOutputVolumeBackend) -> Double {
        switch backend {
        case .software:
            let fraction = clampPercent(sliderPercent) / 100
            return fraction * fraction * 100
        case .hardware, .display, .unavailable:
            return clampPercent(sliderPercent)
        }
    }

    private static func clampPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(100, max(0, value))
    }
}
