import AppKit
import CoreAudio
import Foundation

enum AudioOutputVolumeBackend: String, Equatable {
    case hardware
    case display
    case software
    case unavailable
}

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transportName: String
    var isDefault: Bool
    var volume: Double
    var isMuted: Bool
    let volumeBackend: AudioOutputVolumeBackend
    let supportsVolume: Bool
    let supportsMute: Bool
    let unavailableReason: String?

    var softwareProcessingGain: Double {
        guard volumeBackend == .software else { return 1 }
        guard !isMuted else { return 0 }
        return min(1, max(0, volume / 100))
    }
}

struct AudioProcessTapRoute: Equatable {
    let outputDeviceID: AudioObjectID
    let outputDeviceUID: String
    let outputDevices: [AudioOutputDevice]
    let followsSystemDefault: Bool
    let preferredTapSourceDeviceUID: String?

    init(
        outputDeviceID: AudioObjectID,
        outputDeviceUID: String,
        outputDevices: [AudioOutputDevice]? = nil,
        followsSystemDefault: Bool,
        preferredTapSourceDeviceUID: String?
    ) {
        self.outputDeviceID = outputDeviceID
        self.outputDeviceUID = outputDeviceUID
        self.outputDevices = outputDevices ?? []
        self.followsSystemDefault = followsSystemDefault
        self.preferredTapSourceDeviceUID = preferredTapSourceDeviceUID
    }

    var resolvedOutputDevices: [AudioOutputDevice] {
        outputDevices.isEmpty
            ? [AudioOutputDevice(
                id: outputDeviceID,
                uid: outputDeviceUID,
                name: outputDeviceUID,
                transportName: "",
                isDefault: false,
                volume: 100,
                isMuted: false,
                volumeBackend: .unavailable,
                supportsVolume: false,
                supportsMute: false,
                unavailableReason: nil
            )]
            : outputDevices
    }

    static func == (lhs: AudioProcessTapRoute, rhs: AudioProcessTapRoute) -> Bool {
        lhs.outputDeviceUID == rhs.outputDeviceUID
            && lhs.outputDevices.map(\.uid) == rhs.outputDevices.map(\.uid)
            && lhs.followsSystemDefault == rhs.followsSystemDefault
            && lhs.preferredTapSourceDeviceUID == rhs.preferredTapSourceDeviceUID
    }
}

enum AudioAppOutputRouteIntent: Codable, Equatable {
    case systemDefault
    case single(String)
    case multi([String])

    var primaryOutputDeviceUID: String? {
        switch self {
        case .systemDefault:
            return nil
        case .single(let uid):
            return uid
        case .multi(let uids):
            return uids.first
        }
    }

    var selectedDeviceUIDs: [String] {
        switch self {
        case .systemDefault:
            return []
        case .single(let uid):
            return [uid]
        case .multi(let uids):
            return Self.normalizedUIDs(uids)
        }
    }

    var isMulti: Bool {
        if case .multi = self {
            return true
        }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "systemDefault"
        switch mode {
        case "single":
            if let uid = try container.decodeIfPresent(String.self, forKey: .deviceUID),
               !uid.isEmpty {
                self = .single(uid)
            } else {
                self = .systemDefault
            }
        case "multi":
            let uids = Self.normalizedUIDs(try container.decodeIfPresent([String].self, forKey: .deviceUIDs) ?? [])
            self = uids.isEmpty ? .systemDefault : .multi(uids)
        default:
            self = .systemDefault
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .systemDefault:
            try container.encode("systemDefault", forKey: .mode)
        case .single(let uid):
            try container.encode("single", forKey: .mode)
            try container.encode(uid, forKey: .deviceUID)
        case .multi(let uids):
            try container.encode("multi", forKey: .mode)
            try container.encode(Self.normalizedUIDs(uids), forKey: .deviceUIDs)
        }
    }

    func togglingMultiDevice(_ uid: String) -> AudioAppOutputRouteIntent {
        var uids = selectedDeviceUIDs
        if uids.contains(uid) {
            uids.removeAll { $0 == uid }
        } else {
            uids.append(uid)
        }
        let normalized = Self.normalizedUIDs(uids)
        return normalized.isEmpty ? .systemDefault : .multi(normalized)
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case deviceUID
        case deviceUIDs
    }

    private static func normalizedUIDs(_ uids: [String]) -> [String] {
        var seen = Set<String>()
        return uids.filter { uid in
            guard !uid.isEmpty, !seen.contains(uid) else { return false }
            seen.insert(uid)
            return true
        }
    }
}

enum AudioBoostLevel: Double, CaseIterable, Identifiable {
    case x1 = 1
    case x2 = 2
    case x3 = 3
    case x4 = 4

    var id: Double { rawValue }

    var title: String {
        "\(Int(rawValue))x"
    }
}

struct AudioAppVolumeSettings: Codable, Equatable {
    var volume: Double
    var isMuted: Bool
    var boost: Double
    var outputDeviceUID: String?
    var outputRouteIntent: AudioAppOutputRouteIntent
    var equalizer: AudioEqualizerSettings
    var isPinned: Bool
    var isIgnored: Bool

    static let `default` = AudioAppVolumeSettings(
        volume: 100,
        isMuted: false,
        boost: AudioBoostLevel.x1.rawValue,
        outputDeviceUID: nil,
        outputRouteIntent: .systemDefault,
        equalizer: .flat,
        isPinned: false,
        isIgnored: false
    )

    init(
        volume: Double,
        isMuted: Bool,
        boost: Double,
        outputDeviceUID: String?,
        outputRouteIntent: AudioAppOutputRouteIntent? = nil,
        equalizer: AudioEqualizerSettings = .flat,
        isPinned: Bool,
        isIgnored: Bool
    ) {
        self.volume = volume
        self.isMuted = isMuted
        self.boost = boost
        self.outputDeviceUID = outputDeviceUID
        self.outputRouteIntent = outputRouteIntent ?? outputDeviceUID.map { .single($0) } ?? .systemDefault
        self.equalizer = equalizer
        self.isPinned = isPinned
        self.isIgnored = isIgnored
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outputDeviceUID = try container.decodeIfPresent(String.self, forKey: .outputDeviceUID)
        self.init(
            volume: try container.decodeIfPresent(Double.self, forKey: .volume) ?? Self.default.volume,
            isMuted: try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? Self.default.isMuted,
            boost: try container.decodeIfPresent(Double.self, forKey: .boost) ?? Self.default.boost,
            outputDeviceUID: outputDeviceUID,
            outputRouteIntent: try container.decodeIfPresent(AudioAppOutputRouteIntent.self, forKey: .outputRouteIntent),
            equalizer: try container.decodeIfPresent(AudioEqualizerSettings.self, forKey: .equalizer) ?? .flat,
            isPinned: try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? Self.default.isPinned,
            isIgnored: try container.decodeIfPresent(Bool.self, forKey: .isIgnored) ?? Self.default.isIgnored
        )
    }
}

struct AudioAppVolumeItem: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let processID: pid_t?
    let audioProcessObjectIDs: [AudioObjectID]
    let icon: NSImage?
    let isRunning: Bool
    let isAudible: Bool
    var volume: Double
    var isMuted: Bool
    var boost: AudioBoostLevel
    var outputDeviceUID: String?
    var outputRouteIntent: AudioAppOutputRouteIntent
    var equalizer: AudioEqualizerSettings
    var isPinned: Bool
    var isIgnored: Bool
}

enum AudioCaptureSupportState: Equatable {
    case available
    case permissionRequired(String)
    case unsupported(String)

    var allowsAppAudioControl: Bool {
        if case .available = self {
            return true
        }

        return false
    }

    var message: String? {
        switch self {
        case .available:
            return nil
        case .permissionRequired(let message), .unsupported(let message):
            return message
        }
    }
}

struct AudioProcessInfo: Equatable {
    let objectID: AudioObjectID
    let processID: pid_t
    let bundleIdentifier: String?
    let displayName: String?
    let icon: NSImage?
    let isRunningOutput: Bool
    let isHelperBacked: Bool

    init(
        objectID: AudioObjectID,
        processID: pid_t,
        bundleIdentifier: String?,
        displayName: String? = nil,
        icon: NSImage? = nil,
        isRunningOutput: Bool,
        isHelperBacked: Bool = false
    ) {
        self.objectID = objectID
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.icon = icon
        self.isRunningOutput = isRunningOutput
        self.isHelperBacked = isHelperBacked
    }

    static func == (lhs: AudioProcessInfo, rhs: AudioProcessInfo) -> Bool {
        lhs.objectID == rhs.objectID
            && lhs.processID == rhs.processID
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.displayName == rhs.displayName
            && lhs.isRunningOutput == rhs.isRunningOutput
            && lhs.isHelperBacked == rhs.isHelperBacked
    }
}

struct AudioProcessTapResult {
    let itemID: String
    let success: Bool
    let message: String?
    let statusCode: OSStatus?

    init(itemID: String, success: Bool, message: String?, statusCode: OSStatus? = nil) {
        self.itemID = itemID
        self.success = success
        self.message = message
        self.statusCode = statusCode
    }
}
