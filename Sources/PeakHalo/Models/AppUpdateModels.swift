import Foundation

struct AppUpdateInfo: Equatable, Sendable {
    let currentVersion: String
    let latestVersion: String
    let releaseName: String
    let releaseURL: URL
    let assetURL: URL?
    let publishedAt: Date?
    let isUpdateAvailable: Bool
}

struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
