import Foundation

enum ProcessProtection {
    static let defaultEntries: [String] = [
        "PeakHalo",
        "com.logyxiao.PeakHalo",
        "Finder",
        "com.apple.finder",
        "SystemUIServer",
        "com.apple.systemuiserver",
        "loginwindow",
        "WindowServer",
        "Dock",
        "com.apple.dock"
    ]

    static func isProtected(
        name: String,
        bundleIdentifier: String?,
        whitelist: [String] = defaultEntries,
        currentBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        if let bundleIdentifier, let currentBundleIdentifier, bundleIdentifier == currentBundleIdentifier {
            return true
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBundle = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return whitelist.contains { rawEntry in
            let entry = rawEntry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !entry.isEmpty else { return false }

            if let normalizedBundle, normalizedBundle == entry {
                return true
            }

            return normalizedName == entry || normalizedName.contains(entry)
        }
    }
}
