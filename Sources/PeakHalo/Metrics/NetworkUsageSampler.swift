import Darwin
import Foundation

final class NetworkUsageSampler {
    private var previousCounters: NetworkCounters?

    func sample(at timestamp: Date = Date()) -> NetworkStats {
        guard let counters = Self.readCounters(at: timestamp) else {
            return NetworkStats(
                downloadBytesPerSecond: nil,
                uploadBytesPerSecond: nil,
                receivedBytes: previousCounters?.receivedBytes ?? 0,
                sentBytes: previousCounters?.sentBytes ?? 0
            )
        }

        defer { previousCounters = counters }
        return Self.calculate(previous: previousCounters, current: counters)
    }

    static func calculate(previous: NetworkCounters?, current: NetworkCounters) -> NetworkStats {
        guard let previous else {
            return NetworkStats(
                downloadBytesPerSecond: nil,
                uploadBytesPerSecond: nil,
                receivedBytes: current.receivedBytes,
                sentBytes: current.sentBytes
            )
        }

        let interval = current.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0,
              current.receivedBytes >= previous.receivedBytes,
              current.sentBytes >= previous.sentBytes else {
            return NetworkStats(
                downloadBytesPerSecond: nil,
                uploadBytesPerSecond: nil,
                receivedBytes: current.receivedBytes,
                sentBytes: current.sentBytes
            )
        }

        let receivedDelta = current.receivedBytes - previous.receivedBytes
        let sentDelta = current.sentBytes - previous.sentBytes

        return NetworkStats(
            downloadBytesPerSecond: UInt64(Double(receivedDelta) / interval),
            uploadBytesPerSecond: UInt64(Double(sentDelta) / interval),
            receivedBytes: current.receivedBytes,
            sentBytes: current.sentBytes
        )
    }

    private static func readCounters(at timestamp: Date) -> NetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_UNSPEC, NET_RT_IFLIST2, 0]
        var length: size_t = 0

        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            return nil
        }

        var offset = 0
        var receivedBytes: UInt64 = 0
        var sentBytes: UInt64 = 0

        while offset + MemoryLayout<if_msghdr2>.size <= length {
            var message = if_msghdr2()
            withUnsafeMutableBytes(of: &message) { destination in
                destination.copyBytes(from: buffer[offset ..< offset + MemoryLayout<if_msghdr2>.size])
            }

            guard message.ifm_msglen > 0 else { break }

            if Int32(message.ifm_type) == RTM_IFINFO2 {
                let flags = message.ifm_flags
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                let isUp = (flags & IFF_UP) != 0

                if !isLoopback, isUp {
                    receivedBytes += UInt64(message.ifm_data.ifi_ibytes)
                    sentBytes += UInt64(message.ifm_data.ifi_obytes)
                }
            }

            offset += Int(message.ifm_msglen)
        }

        return NetworkCounters(
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            timestamp: timestamp
        )
    }
}
