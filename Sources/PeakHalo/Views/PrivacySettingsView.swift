import AppKit
import CoreBluetooth
import SwiftUI

struct PermissionsSettingsView: View {
    @ObservedObject private var audioPermission = AudioRecordingPermissionController.shared
    @State private var bluetoothAuthorization = CBManager.authorization

    var body: some View {
        Form {
            Section {
                permissionRow(
                    title: "Screen & System Audio Recording",
                    subtitle: "Required for per-app volume, mute, boost, equalizer, and playback device routing.",
                    systemImage: "waveform.badge.magnifyingglass",
                    iconTint: .purple,
                    status: audioPermissionStatus
                ) {
                    Button("Request Access") {
                        requestAudioCapturePermission()
                    }
                    .disabled(audioPermission.status == .authorized || audioPermission.status == .unsupported)

                    Button("Open System Settings") {
                        openSystemSettings(anchor: "Privacy_ScreenCapture")
                    }

                    Button("Check Again") {
                        _ = audioPermission.refreshStatus()
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Screen & Audio Capture")
            }

            Section {
                permissionRow(
                    title: "Bluetooth",
                    subtitle: "Used to show battery levels for connected accessories.",
                    systemImage: "bluetooth",
                    iconTint: .blue,
                    status: bluetoothPermissionStatus
                ) {
                    Button("Open System Settings") {
                        openSystemSettings(anchor: "Privacy_Bluetooth")
                    }

                    Button("Check Again") {
                        refreshBluetoothAuthorization()
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Bluetooth Accessory Access")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            _ = audioPermission.refreshStatus()
            refreshBluetoothAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            _ = audioPermission.refreshStatus()
            refreshBluetoothAuthorization()
        }
    }

    private var audioPermissionStatus: PermissionStatusPresentation {
        switch audioPermission.status {
        case .authorized:
            return .authorized
        case .unknown:
            return .notDetermined
        case .denied:
            return .denied
        case .unsupported:
            return .unsupported
        }
    }

    private var bluetoothPermissionStatus: PermissionStatusPresentation {
        switch bluetoothAuthorization {
        case .allowedAlways:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unknown
        }
    }

    private func permissionRow<Actions: View>(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        iconTint: Color,
        status: PermissionStatusPresentation,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [iconTint, iconTint.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.headline)

                        statusBadge(status)
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }

            HStack(spacing: 8) {
                actions()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.leading, 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBadge(_ status: PermissionStatusPresentation) -> some View {
        Label {
            Text(status.title)
        } icon: {
            Image(systemName: status.symbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(status.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.tint.opacity(0.12), in: Capsule())
    }

    private func requestAudioCapturePermission() {
        audioPermission.resetRequestSuppressionForUserRetry()
        audioPermission.requestIfNeeded { _ in
            _ = audioPermission.refreshStatus()
        }
    }

    private func refreshBluetoothAuthorization() {
        bluetoothAuthorization = CBManager.authorization
    }

    private func openSystemSettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct PermissionStatusPresentation {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color

    static let authorized = PermissionStatusPresentation(
        title: "Allowed",
        symbol: "checkmark.circle.fill",
        tint: .green
    )

    static let denied = PermissionStatusPresentation(
        title: "Denied",
        symbol: "xmark.circle.fill",
        tint: .red
    )

    static let restricted = PermissionStatusPresentation(
        title: "Restricted",
        symbol: "lock.circle.fill",
        tint: .orange
    )

    static let notDetermined = PermissionStatusPresentation(
        title: "Not Determined",
        symbol: "questionmark.circle.fill",
        tint: .orange
    )

    static let unsupported = PermissionStatusPresentation(
        title: "Unsupported",
        symbol: "exclamationmark.triangle.fill",
        tint: .secondary
    )

    static let unknown = PermissionStatusPresentation(
        title: "Unknown",
        symbol: "questionmark.circle",
        tint: .secondary
    )
}
