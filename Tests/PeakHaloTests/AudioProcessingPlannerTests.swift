import CoreAudio
import Testing
@testable import PeakHalo

@Suite("Audio processing planner")
struct AudioProcessingPlannerTests {
    @Test("Planner deactivates missing ignored or silent processing items")
    func deactivatesInvalidProcessingItems() {
        let plan = AudioProcessingPlanner.plan(
            processingItemIDs: ["missing", "ignored", "silent"],
            pendingItemIDs: [],
            manuallyDisabledItemIDs: [],
            previousItems: [:],
            currentItems: [
                appItem(id: "ignored", isAudible: true, isIgnored: true, objectIDs: [1]),
                appItem(id: "silent", isAudible: false, isIgnored: false, objectIDs: [2])
            ]
        )

        #expect(plan.deactivateItemIDs == ["ignored", "missing", "silent"])
        #expect(plan.restartItemIDs.isEmpty)
        #expect(plan.activatePendingItemIDs.isEmpty)
    }

    @Test("Planner restarts processing when process object IDs change")
    func restartsWhenProcessObjectIDsChange() {
        let plan = AudioProcessingPlanner.plan(
            processingItemIDs: ["app"],
            pendingItemIDs: [],
            manuallyDisabledItemIDs: [],
            previousItems: ["app": appItem(id: "app", isAudible: true, isIgnored: false, objectIDs: [1])],
            currentItems: [appItem(id: "app", isAudible: true, isIgnored: false, objectIDs: [2])]
        )

        #expect(plan.deactivateItemIDs.isEmpty)
        #expect(plan.restartItemIDs == ["app"])
        #expect(plan.activatePendingItemIDs.isEmpty)
    }

    @Test("Planner activates pending items only when eligible")
    func activatesEligiblePendingItems() {
        let plan = AudioProcessingPlanner.plan(
            processingItemIDs: [],
            pendingItemIDs: ["ready", "manual", "ignored", "empty"],
            manuallyDisabledItemIDs: ["manual"],
            previousItems: [:],
            currentItems: [
                appItem(id: "ready", isAudible: true, isIgnored: false, objectIDs: [1]),
                appItem(id: "manual", isAudible: true, isIgnored: false, objectIDs: [2]),
                appItem(id: "ignored", isAudible: true, isIgnored: true, objectIDs: [3]),
                appItem(id: "empty", isAudible: true, isIgnored: false, objectIDs: [])
            ]
        )

        #expect(plan.deactivateItemIDs.isEmpty)
        #expect(plan.restartItemIDs.isEmpty)
        #expect(plan.activatePendingItemIDs == ["ready"])
    }

    private func appItem(
        id: String,
        isAudible: Bool,
        isIgnored: Bool,
        objectIDs: [AudioObjectID]
    ) -> AudioAppVolumeItem {
        AudioAppVolumeItem(
            id: id,
            name: id,
            bundleIdentifier: nil,
            processID: 123,
            audioProcessObjectIDs: objectIDs,
            icon: nil,
            isRunning: true,
            isAudible: isAudible,
            volume: 100,
            isMuted: false,
            boost: .x1,
            outputDeviceUID: nil,
            outputRouteIntent: .systemDefault,
            equalizer: .flat,
            isPinned: false,
            isIgnored: isIgnored
        )
    }
}
