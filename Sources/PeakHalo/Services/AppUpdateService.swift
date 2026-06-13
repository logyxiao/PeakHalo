import Foundation

enum AppUpdateError: LocalizedError, Sendable {
    case invalidResponse
    case noRelease

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "Could not read update information.")
        case .noRelease:
            String(localized: "No GitHub release is available yet.")
        }
    }
}

struct AppUpdateService {
    static var repositoryURL: URL {
        URL(string: "https://github.com/\(repositorySlug)")!
    }

    private static var repositorySlug: String {
        normalizedRepositorySlug(
            Bundle.main.object(forInfoDictionaryKey: "PeakHaloGitHubRepository") as? String
        )
    }

    private static var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repositorySlug)/releases/latest")!
    }

    static func checkForUpdates(currentVersion: String) async throws -> AppUpdateInfo {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PeakHalo", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw AppUpdateError.noRelease
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: data)
        let latestVersion = normalizedVersion(release.tagName)
        let assetURL = preferredAssetURL(from: release.assets)
        let isUpdateAvailable = compareVersions(latestVersion, currentVersion) == .orderedDescending

        return AppUpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseName: release.name ?? release.tagName,
            releaseURL: release.htmlURL,
            assetURL: assetURL,
            publishedAt: release.publishedAt,
            isUpdateAvailable: isUpdateAvailable
        )
    }

    private static func preferredAssetURL(from assets: [GitHubReleaseAsset]) -> URL? {
        let lowercasedAssets = assets.map { ($0, $0.name.lowercased()) }
        return lowercasedAssets.first { $0.1.hasSuffix(".dmg") }?.0.browserDownloadURL
            ?? lowercasedAssets.first { $0.1.hasSuffix(".pkg") }?.0.browserDownloadURL
            ?? lowercasedAssets.first { $0.1.hasSuffix(".zip") }?.0.browserDownloadURL
    }

    private static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("v") else { return trimmed }
        return String(trimmed.dropFirst())
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue > rightValue { return .orderedDescending }
            if leftValue < rightValue { return .orderedAscending }
        }

        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split { !$0.isNumber }
            .prefix(4)
            .map { Int($0) ?? 0 }
    }

    private static func normalizedRepositorySlug(_ rawValue: String?) -> String {
        let fallback = "logyxiao/PeakHalo"
        guard let rawValue else { return fallback }

        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".git", with: "")

        guard !trimmed.isEmpty else { return fallback }

        if trimmed.contains("github.com/"),
           let range = trimmed.range(of: "github.com/") {
            return normalizedRepositorySlug(String(trimmed[range.upperBound...]))
        }

        if trimmed.contains("github.com:"),
           let range = trimmed.range(of: "github.com:") {
            return normalizedRepositorySlug(String(trimmed[range.upperBound...]))
        }

        let parts = trimmed.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return fallback }

        return "\(parts[0])/\(parts[1])"
    }
}
