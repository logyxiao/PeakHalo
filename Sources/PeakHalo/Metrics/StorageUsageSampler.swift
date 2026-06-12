import Foundation

final class StorageUsageSampler {
    func sample() -> StorageStats? {
        do {
            let rootURL = URL(fileURLWithPath: "/")
            let values = try rootURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: "/")
            let total = UInt64(
                values.volumeTotalCapacity
                    ?? Int((attributes[.systemSize] as? NSNumber)?.int64Value ?? 0)
            )
            let free = UInt64(
                values.volumeAvailableCapacity
                    ?? Int((attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
            )

            return Self.calculate(
                totalBytes: total,
                freeBytes: free,
                externalVolumes: detectExternalVolumes()
            )
        } catch {
            return nil
        }
    }

    static func calculate(
        totalBytes: UInt64,
        freeBytes: UInt64,
        externalVolumes: [StorageVolumeStats]
    ) -> StorageStats {
        StorageStats(
            usedBytes: totalBytes >= freeBytes ? totalBytes - freeBytes : 0,
            freeBytes: min(freeBytes, totalBytes),
            totalBytes: totalBytes,
            externalVolumes: Array(externalVolumes.filter { $0.totalBytes > 0 }.prefix(3))
        )
    }

    private func detectExternalVolumes() -> [StorageVolumeStats] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeNameKey,
                .volumeIsInternalKey
            ],
            options: []
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeNameKey,
                .volumeIsInternalKey
            ]),
                  values.volumeIsInternal == false,
                  let total = values.volumeTotalCapacity,
                  let free = values.volumeAvailableCapacity,
                  total > 0 else {
                return nil
            }

            let totalBytes = UInt64(total)
            let freeBytes = UInt64(max(0, free))
            let usedBytes = totalBytes >= freeBytes ? totalBytes - freeBytes : 0
            let name = values.volumeName ?? url.lastPathComponent
            return StorageVolumeStats(
                id: "\(name)-\(totalBytes)",
                name: name,
                usedBytes: usedBytes,
                freeBytes: min(freeBytes, totalBytes),
                totalBytes: totalBytes
            )
        }
        .prefix(3)
        .map { $0 }
    }
}
