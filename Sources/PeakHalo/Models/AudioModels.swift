import AppKit
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transportName: String
    var isDefault: Bool
    var volume: Double
    var isMuted: Bool
    let supportsVolume: Bool
    let supportsMute: Bool
    let unavailableReason: String?
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
    var isPinned: Bool
    var isIgnored: Bool

    static let `default` = AudioAppVolumeSettings(
        volume: 100,
        isMuted: false,
        boost: AudioBoostLevel.x1.rawValue,
        outputDeviceUID: nil,
        isPinned: false,
        isIgnored: false
    )
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
    let isRunningOutput: Bool
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
