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
            previousItems: [:],
            currentItems: [
                appItem(id: "ignored", isAudible: true, isIgnored: true, objectIDs: [1]),
                appItem(id: "silent", isAudible: false, isIgnored: false, objectIDs: [2])
            ]
        )

        #expect(plan.deactivateItemIDs == ["ignored", "missing", "silent"])
        #expect(plan.restartItemIDs.isEmpty)
        #expect(plan.activateItemIDs.isEmpty)
    }

    @Test("Planner restarts processing when process object IDs change")
    func restartsWhenProcessObjectIDsChange() {
        let plan = AudioProcessingPlanner.plan(
            processingItemIDs: ["app"],
            pendingItemIDs: [],
            previousItems: ["app": appItem(id: "app", isAudible: true, isIgnored: false, objectIDs: [1])],
            currentItems: [appItem(id: "app", isAudible: true, isIgnored: false, objectIDs: [2])]
        )

        #expect(plan.deactivateItemIDs.isEmpty)
        #expect(plan.restartItemIDs == ["app"])
        #expect(plan.activateItemIDs.isEmpty)
    }

    @Test("Planner activates unprocessed audible and eligible pending items")
    func activatesUnprocessedEligibleItems() {
        let plan = AudioProcessingPlanner.plan(
            processingItemIDs: ["already"],
            pendingItemIDs: ["pending"],
            previousItems: [:],
            currentItems: [
                appItem(id: "already", isAudible: true, isIgnored: false, objectIDs: [1]),
                appItem(id: "audible", isAudible: true, isIgnored: false, objectIDs: [2]),
                appItem(id: "pending", isAudible: false, isIgnored: false, objectIDs: [3]),
                appItem(id: "ignored", isAudible: true, isIgnored: true, objectIDs: [4]),
                appItem(id: "silent", isAudible: false, isIgnored: false, objectIDs: [5]),
                appItem(id: "empty", isAudible: true, isIgnored: false, objectIDs: [])
            ]
        )

        #expect(plan.deactivateItemIDs.isEmpty)
        #expect(plan.restartItemIDs.isEmpty)
        #expect(plan.activateItemIDs == ["audible", "pending"])
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
