import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject private var updateStore = AppUpdateStore.shared

    var body: some View {
        Form {
            Section {
                appSummary
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    updateStatus
                    updateActions
                }
                .padding(.vertical, 4)
            } header: {
                Text("GitHub Updates")
            } footer: {
                Text("Check GitHub Releases for new installer packages.")
            }

            Section {
                licenseSummary
            } header: {
                Text("Open Source Credits")
            } footer: {
                Text("Audio controls are adapted from FineTune under GPLv3-compatible terms.")
            }
        }
        .formStyle(.grouped)
        .task {
            await updateStore.checkForUpdatesIfNeeded()
        }
    }

    private var appSummary: some View {
        VStack(spacing: 8) {
            appLogo
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .padding(.bottom, 4)

            Text("PeakHalo")
                .font(.title2.weight(.bold))

            Text("A premium notch overlay & control center for macOS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

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
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var appLogo: some View {
        if let image = Self.appLogoImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.teal, .blue, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "waveform")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
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
        HStack(spacing: 8) {
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
            .buttonStyle(.borderedProminent)

            Button {
                updateStore.openReleasePage()
            } label: {
                Label("Open GitHub", systemImage: "arrow.up.right.square")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var licenseSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PeakHalo incorporates GPLv3-compatible audio-control architecture and implementation techniques derived from FineTune.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
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
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
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
