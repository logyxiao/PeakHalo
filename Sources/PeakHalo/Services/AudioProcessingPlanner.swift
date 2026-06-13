import Foundation

struct AudioProcessingPlan: Equatable {
    let deactivateItemIDs: [String]
    let restartItemIDs: [String]
    let activatePendingItemIDs: [String]
}

enum AudioProcessingPlanner {
    static func plan(
        processingItemIDs: Set<String>,
        pendingItemIDs: Set<String>,
        manuallyDisabledItemIDs: Set<String>,
        previousItems: [String: AudioAppVolumeItem],
        currentItems: [AudioAppVolumeItem]
    ) -> AudioProcessingPlan {
        let currentItemsByID = Dictionary(
            currentItems.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )

        var deactivateItemIDs: [String] = []
        var restartItemIDs: [String] = []

        for itemID in processingItemIDs.sorted() {
            guard let item = currentItemsByID[itemID],
                  item.isAudible,
                  !item.isIgnored else {
                deactivateItemIDs.append(itemID)
                continue
            }

            guard let previous = previousItems[itemID] else { continue }
            if previous.audioProcessObjectIDs != item.audioProcessObjectIDs {
                restartItemIDs.append(itemID)
            }
        }

        let activatePendingItemIDs = currentItems
            .filter { item in
                pendingItemIDs.contains(item.id)
                    && !manuallyDisabledItemIDs.contains(item.id)
                    && !item.isIgnored
                    && !item.audioProcessObjectIDs.isEmpty
            }
            .map(\.id)
            .sorted()

        return AudioProcessingPlan(
            deactivateItemIDs: deactivateItemIDs,
            restartItemIDs: restartItemIDs,
            activatePendingItemIDs: activatePendingItemIDs
        )
    }
}
