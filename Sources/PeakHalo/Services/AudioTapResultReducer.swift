import CoreAudio
import Foundation

struct AudioTapResultState: Equatable {
    var processingItemIDs: Set<String>
    var pendingItemIDs: Set<String>
    var fallbackRoutedItemIDs: Set<String>
}

struct AudioTapResultReduction: Equatable {
    let state: AudioTapResultState
    let message: LocalizedMessage?
    let permissionDenied: Bool
    let shouldResortItems: Bool
}

enum AudioTapResultReducer {
    static func reduce(
        result: AudioProcessTapResult,
        enabling: Bool,
        state: AudioTapResultState
    ) -> AudioTapResultReduction {
        var nextState = state

        guard result.success else {
            if result.statusCode == kAudioDevicePermissionsError {
                let message = LocalizedMessage.string("Grant Screen & System Audio Recording permission to adjust per-app volume.")
                return AudioTapResultReduction(
                    state: nextState,
                    message: message,
                    permissionDenied: true,
                    shouldResortItems: false
                )
            }

            return AudioTapResultReduction(
                state: nextState,
                message: result.message,
                permissionDenied: false,
                shouldResortItems: false
            )
        }

        if enabling {
            nextState.processingItemIDs.insert(result.itemID)
            nextState.pendingItemIDs.remove(result.itemID)
            let usedFallback = nextState.fallbackRoutedItemIDs.remove(result.itemID) != nil
            return AudioTapResultReduction(
                state: nextState,
                message: usedFallback
                    ? .string("Selected output is unavailable. Using System Default.")
                    : nil,
                permissionDenied: false,
                shouldResortItems: true
            )
        }

        nextState.processingItemIDs.remove(result.itemID)
        return AudioTapResultReduction(
            state: nextState,
            message: nil,
            permissionDenied: false,
            shouldResortItems: true
        )
    }
}
