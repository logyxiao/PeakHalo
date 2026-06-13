import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject private var updateStore = AppUpdateStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            appSummary

            Divider()

            settingsHeader(
                title: "GitHub Updates",
                subtitle: "Check GitHub Releases for new installer packages."
            )

            updateStatus
            updateActions

            Divider()

            settingsHeader(
                title: "Open Source Audio",
                subtitle: "Audio controls are adapted from FineTune under GPLv3-compatible terms."
            )

            licenseSummary
        }
        .task {
            await updateStore.checkForUpdatesIfNeeded()
        }
    }

    private var appSummary: some View {
        HStack(alignment: .center, spacing: 14) {
            appLogo

            VStack(alignment: .leading, spacing: 5) {
                Text("PeakHalo")
                    .font(.title3.weight(.semibold))

                Text("Notch Monitor")
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    versionBadge(
                        title: "Version",
                        value: updateStore.currentVersion
                    )
                    versionBadge(
                        title: "Build",
                        value: updateStore.currentBuild
                    )
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var appLogo: some View {
        if let image = Self.appLogoImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.teal.opacity(0.16))
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.teal)
                }
        }
    }

    private static var appLogoImage: NSImage? {
        if let url = Bundle.main.url(forResource: "AppLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        guard let resourceURL = Bundle.main.resourceURL,
              let resourceURLs = try? FileManager.default.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: nil
              ) else {
            return nil
        }

        for bundleURL in resourceURLs where bundleURL.pathExtension == "bundle" {
            guard let bundle = Bundle(url: bundleURL),
                  let url = bundle.url(forResource: "AppLogo", withExtension: "png"),
                  let image = NSImage(contentsOf: url) else {
                continue
            }
            return image
        }

        return nil
    }

    private func versionBadge(title: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    @ViewBuilder
    private var updateStatus: some View {
        if updateStore.isChecking {
            Label("Checking for updates...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        } else if let errorMessage = updateStore.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if let latestUpdate = updateStore.latestUpdate {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    latestUpdate.isUpdateAvailable ? "Update Available" : "Up to Date",
                    systemImage: latestUpdate.isUpdateAvailable ? "arrow.down.circle" : "checkmark.circle"
                )
                .foregroundStyle(latestUpdate.isUpdateAvailable ? .blue : .green)

                Text(updateDescription(for: latestUpdate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let statusMessage = updateStore.statusMessage {
            Text(statusMessage)
                .foregroundStyle(.secondary)
        }
    }

    private var updateActions: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await updateStore.checkForUpdates()
                }
            } label: {
                Label("Check for Updates", systemImage: "arrow.clockwise")
            }
            .disabled(updateStore.isChecking)

            Button {
                updateStore.openDownload()
            } label: {
                Label("Download Update", systemImage: "arrow.down.circle")
            }
            .disabled(updateStore.latestUpdate?.isUpdateAvailable != true)

            Button {
                updateStore.openReleasePage()
            } label: {
                Label("Open GitHub", systemImage: "arrow.up.right.square")
            }
        }
    }

    private var licenseSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PeakHalo incorporates GPLv3-compatible audio-control architecture and implementation techniques derived from FineTune.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    openURL("https://github.com/ronitsingh10/FineTune")
                } label: {
                    Label("FineTune", systemImage: "arrow.up.right.square")
                }

                Button {
                    openURL("https://www.gnu.org/licenses/gpl-3.0.html")
                } label: {
                    Label("GPLv3", systemImage: "doc.text")
                }
            }
        }
    }

    private func updateDescription(for info: AppUpdateInfo) -> String {
        let base = String.localizedStringWithFormat(
            String(localized: "Latest version: %@"),
            info.latestVersion
        )

        guard let publishedAt = info.publishedAt else { return base }

        return base + " · " + publishedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
