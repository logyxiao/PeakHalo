import AppKit
import Darwin
import Foundation

@MainActor
final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private var lockFileDescriptor: Int32 = -1

    private init() {}

    func acquireReplacingOtherInstances(timeout: TimeInterval = 1.5) -> Bool {
        if acquire() {
            terminateOtherInstances()
            return true
        }

        terminateOtherInstances()
        if waitForLock(until: Date().addingTimeInterval(timeout * 0.5)) {
            return true
        }

        terminateOtherInstances(force: true)
        return waitForLock(until: Date().addingTimeInterval(timeout * 0.5))
    }

    func acquire() -> Bool {
        guard lockFileDescriptor == -1 else { return true }

        let lockPath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("com.logyxiao.PeakHalo.lock")
            .path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return true }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            lockFileDescriptor = descriptor
            return true
        }

        close(descriptor)
        return false
    }

    func release() {
        guard lockFileDescriptor >= 0 else { return }
        flock(lockFileDescriptor, LOCK_UN)
        close(lockFileDescriptor)
        lockFileDescriptor = -1
    }

    func terminateOtherInstances(force: Bool = false) {
        let currentProcessID = getpid()

        for application in NSWorkspace.shared.runningApplications {
            guard application.processIdentifier != currentProcessID,
                  application.executableURL?.lastPathComponent == "PeakHalo"
                    || application.localizedName == "PeakHalo" else {
                continue
            }

            if force {
                application.forceTerminate()
            } else {
                application.terminate()
            }
        }
    }

    private func waitForLock(until deadline: Date) -> Bool {
        while Date() < deadline {
            if acquire() {
                return true
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        return acquire()
    }
}
