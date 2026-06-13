import AppKit
import Combine
import Foundation
import os

enum AudioRecordingPermissionStatus: Equatable {
    case unknown
    case authorized
    case denied
    case unsupported
}

@MainActor
final class AudioRecordingPermissionController: ObservableObject {
    static let shared = AudioRecordingPermissionController()

    @Published private(set) var status: AudioRecordingPermissionStatus

    private let defaults: UserDefaults
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PeakHalo",
        category: "AudioRecordingPermission"
    )
    private var activationObserver: NSObjectProtocol?
    private var hasRequestedInProcess = false

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.status = Self.preflight()
        registerForActivation()
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    @discardableResult
    func refreshStatus() -> AudioRecordingPermissionStatus {
        let nextStatus = Self.preflight()
        status = nextStatus
        return nextStatus
    }

    func requestIfNeeded(completion: @escaping (AudioRecordingPermissionStatus) -> Void) {
        refreshStatus()
        guard status == .unknown else {
            completion(status)
            return
        }

        guard !hasRequestedInProcess, !defaults.bool(forKey: Self.requestedDefaultsKey) else {
            completion(status)
            return
        }

        hasRequestedInProcess = true
        defaults.set(true, forKey: Self.requestedDefaultsKey)

        Self.requestAccess { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.status = granted ? .authorized : Self.preflight()
                self.logger.info("Audio capture permission request completed: \(granted, privacy: .public)")
                completion(self.status)
            }
        }
    }

    func markDenied() {
        status = .denied
    }

    func resetRequestSuppressionForUserRetry() {
        hasRequestedInProcess = false
        defaults.set(false, forKey: Self.requestedDefaultsKey)
    }

    private func registerForActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.refreshStatus()
            }
        }
    }

    private static let requestedDefaultsKey = "audio.capturePermission.didRequest"
    private static let tccFrameworkPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"
    private static let serviceName = "kTCCServiceAudioCapture"

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static func preflight() -> AudioRecordingPermissionStatus {
        guard #available(macOS 14.4, *) else {
            return .unsupported
        }

        guard let handle = dlopen(tccFrameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessPreflight") else {
            return .unknown
        }

        let function = unsafeBitCast(symbol, to: PreflightFunction.self)
        switch function(serviceName as CFString, nil) {
        case 0:
            return .authorized
        case 1:
            return .denied
        default:
            return .unknown
        }
    }

    private static func requestAccess(completion: @escaping (Bool) -> Void) {
        guard #available(macOS 14.4, *) else {
            completion(false)
            return
        }

        guard let handle = dlopen(tccFrameworkPath, RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessRequest") else {
            completion(false)
            return
        }

        let function = unsafeBitCast(symbol, to: RequestFunction.self)
        function(serviceName as CFString, nil, completion)
    }
}
