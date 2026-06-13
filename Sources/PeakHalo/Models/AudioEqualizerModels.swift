import Foundation

struct AudioEqualizerSettings: Codable, Equatable {
    static let bandCount = 10
    static let minGainDB = -12.0
    static let maxGainDB = 12.0
    static let frequencies: [Double] = [
        31.25, 62.5, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000
    ]

    var bandGains: [Double]
    var isEnabled: Bool

    init(
        bandGains: [Double] = Array(repeating: 0, count: AudioEqualizerSettings.bandCount),
        isEnabled: Bool = false
    ) {
        self.bandGains = Self.normalizedBandGains(bandGains)
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bandGains = Self.normalizedBandGains(
            try container.decodeIfPresent([Double].self, forKey: .bandGains)
                ?? Array(repeating: 0, count: Self.bandCount)
        )
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }

    var clampedBandGains: [Double] {
        bandGains.map(Self.clampGain)
    }

    static let flat = AudioEqualizerSettings()

    static func normalizedBandGains(_ gains: [Double]) -> [Double] {
        let normalized: [Double]
        if gains.count >= bandCount {
            normalized = Array(gains.prefix(bandCount))
        } else {
            normalized = gains + Array(repeating: 0, count: bandCount - gains.count)
        }

        return normalized.map(clampGain)
    }

    static func clampGain(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(maxGainDB, max(minGainDB, value))
    }
}

enum AudioEqualizerPreset: String, CaseIterable, Identifiable {
    case flat
    case bassBoost
    case trebleBoost
    case vocalClarity
    case podcast
    case loudness
    case lateNight
    case rock
    case pop
    case electronic
    case jazz
    case movie

    var id: String { rawValue }

    var name: String {
        switch self {
        case .flat: return "Flat"
        case .bassBoost: return "Bass Boost"
        case .trebleBoost: return "Treble Boost"
        case .vocalClarity: return "Vocal Clarity"
        case .podcast: return "Podcast"
        case .loudness: return "Loudness"
        case .lateNight: return "Late Night"
        case .rock: return "Rock"
        case .pop: return "Pop"
        case .electronic: return "Electronic"
        case .jazz: return "Jazz"
        case .movie: return "Movie"
        }
    }

    var settings: AudioEqualizerSettings {
        AudioEqualizerSettings(bandGains: gains, isEnabled: self != .flat)
    }

    private var gains: [Double] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost:
            return [6, 6, 5, -1, 0, 0, 0, 0, 0, 0]
        case .trebleBoost:
            return [0, 0, 0, 0, 0, 0, 2, 4, 5, 6]
        case .vocalClarity:
            return [-4, -2, -1, -3, 0, 2, 4, 4, 1, 0]
        case .podcast:
            return [-6, -4, -2, -1, 0, 2, 4, 3, 1, 0]
        case .loudness:
            return [5, 4, 2, 0, -2, -2, 0, 2, 4, 5]
        case .lateNight:
            return [-6, -4, -2, 0, 0, 1, 2, 2, 1, 0]
        case .rock:
            return [4, 3, 2, 0, -1, 0, 2, 3, 2, 1]
        case .pop:
            return [3, 3, 2, 0, -1, 1, 2, 3, 3, 4]
        case .electronic:
            return [7, 6, 4, 0, -2, -2, 1, 3, 4, 3]
        case .jazz:
            return [3, 2, 1, 0, 0, 0, 1, 2, 2, 1]
        case .movie:
            return [4, 4, 3, -1, -1, 1, 3, 3, 2, 1]
        }
    }
}
