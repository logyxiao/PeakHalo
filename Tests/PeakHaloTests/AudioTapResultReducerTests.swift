import CoreAudio
import Testing
@testable import PeakHalo

@Suite("Audio tap result reducer")
struct AudioTapResultReducerTests {
    @Test("Successful enable marks processing and clears pending manual and fallback state")
    func successfulEnableUpdatesState() {
        let reduction = AudioTapResultReducer.reduce(
            result: AudioProcessTapResult(itemID: "app", success: true, message: nil),
            enabling: true,
            state: AudioTapResultState(
                processingItemIDs: [],
                pendingItemIDs: ["app"],
                fallbackRoutedItemIDs: ["app"]
            )
        )

        #expect(reduction.state.processingItemIDs == ["app"])
        #expect(reduction.state.pendingItemIDs.isEmpty)
        #expect(reduction.state.fallbackRoutedItemIDs.isEmpty)
        #expect(reduction.message == .string("Selected output is unavailable. Using System Default."))
        #expect(reduction.shouldResortItems)
        #expect(reduction.permissionDenied == false)
    }

    @Test("Successful disable removes processing state")
    func successfulDisableUpdatesState() {
        let reduction = AudioTapResultReducer.reduce(
            result: AudioProcessTapResult(itemID: "app", success: true, message: nil),
            enabling: false,
            state: AudioTapResultState(
                processingItemIDs: ["app"],
                pendingItemIDs: [],
                fallbackRoutedItemIDs: []
            )
        )

        #expect(reduction.state.processingItemIDs.isEmpty)
        #expect(reduction.message == nil)
        #expect(reduction.shouldResortItems)
    }

    @Test("Permission failure requests permission state update")
    func permissionFailureRequestsPermissionStateUpdate() {
        let reduction = AudioTapResultReducer.reduce(
            result: AudioProcessTapResult(
                itemID: "app",
                success: false,
                message: .string("raw failure"),
                statusCode: kAudioDevicePermissionsError
            ),
            enabling: true,
            state: AudioTapResultState(
                processingItemIDs: [],
                pendingItemIDs: [],
                fallbackRoutedItemIDs: []
            )
        )

        #expect(reduction.permissionDenied)
        #expect(reduction.message == .string("Grant Screen & System Audio Recording permission to adjust per-app volume."))
        #expect(reduction.shouldResortItems == false)
    }
}
