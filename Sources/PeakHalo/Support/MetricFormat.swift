import Foundation

enum MetricFormat {
    static func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    static func processPercent(_ value: Double) -> String {
        guard value.isFinite else { return "0%" }
        if value >= 10 {
            return "\(Int(value.rounded()))%"
        }
        return String(format: "%.1f%%", max(0, value))
    }

    static func bytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "--" }
        return scaledBytes(bytes, suffix: "")
    }

    static func rate(_ bytesPerSecond: UInt64?) -> String {
        guard let bytesPerSecond else { return "--" }
        return scaledBytes(bytesPerSecond, suffix: "/s")
    }

    static func temperature(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(value.rounded()))C"
    }

    static func fanSpeed(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(value.rounded())) RPM"
    }

    static func power(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(format: "%.1fW", max(0, value))
    }

    static func time(_ date: Date) -> String {
        guard date != .distantPast else { return "--:--:--" }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func scaledBytes(_ bytes: UInt64, suffix: String) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0

        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }

        if index == 0 {
            return "\(Int(value))\(units[index])\(suffix)"
        }

        if value >= 10 {
            return "\(Int(value.rounded()))\(units[index])\(suffix)"
        }

        return String(format: "%.1f%@%@", value, units[index], suffix)
    }
}
