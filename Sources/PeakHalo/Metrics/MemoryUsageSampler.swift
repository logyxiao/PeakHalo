import Darwin
import Foundation

final class MemoryUsageSampler {
    func sample() -> MemoryStats {
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryStats(
                usedBytes: 0,
                appBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                swapUsedBytes: Self.readSwapUsedBytes(),
                totalBytes: totalBytes
            )
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        return Self.calculate(
            pageCounts: MemoryPageCounts(
                internalPages: UInt64(stats.internal_page_count),
                purgeablePages: UInt64(stats.purgeable_count),
                wiredPages: UInt64(stats.wire_count),
                compressedPages: UInt64(stats.compressor_page_count),
                externalPages: UInt64(stats.external_page_count),
                speculativePages: UInt64(stats.speculative_count)
            ),
            pageSize: UInt64(pageSize),
            totalBytes: totalBytes,
            swapUsedBytes: Self.readSwapUsedBytes()
        )
    }

    static func calculate(
        pageCounts: MemoryPageCounts,
        pageSize: UInt64,
        totalBytes: UInt64,
        swapUsedBytes: UInt64
    ) -> MemoryStats {
        guard pageSize > 0 else {
            return MemoryStats(
                usedBytes: 0,
                appBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0,
                swapUsedBytes: swapUsedBytes,
                totalBytes: totalBytes
            )
        }

        let appPages = pageCounts.internalPages > pageCounts.purgeablePages
            ? pageCounts.internalPages - pageCounts.purgeablePages
            : pageCounts.internalPages
        let cachedPages = pageCounts.externalPages
            + pageCounts.purgeablePages
            + pageCounts.speculativePages

        let appBytes = bytes(for: appPages, pageSize: pageSize)
        let wiredBytes = bytes(for: pageCounts.wiredPages, pageSize: pageSize)
        let compressedBytes = bytes(for: pageCounts.compressedPages, pageSize: pageSize)
        let cachedBytes = bytes(for: cachedPages, pageSize: pageSize)
        let usedBytes = min(totalBytes, appBytes + wiredBytes + compressedBytes)

        return MemoryStats(
            usedBytes: usedBytes,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedBytes: cachedBytes,
            swapUsedBytes: swapUsedBytes,
            totalBytes: totalBytes
        )
    }

    private static func bytes(for pages: UInt64, pageSize: UInt64) -> UInt64 {
        let (value, overflow) = pages.multipliedReportingOverflow(by: pageSize)
        return overflow ? UInt64.max : value
    }

    private static func readSwapUsedBytes() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: size) {
                sysctlbyname("vm.swapusage", $0, &size, nil, 0)
            }
        }

        guard result == 0 else { return 0 }
        return UInt64(usage.xsu_used)
    }
}
