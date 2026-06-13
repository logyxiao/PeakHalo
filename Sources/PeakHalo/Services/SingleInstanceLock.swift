import AppKit
import Darwin
import Foundation

@MainActor
final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private static let fallbackBundleIdentifier = "com.logyxiao.PeakHalo"
    private static let executableName = "PeakHalo"
    private static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier
    }
    private var lockFileDescriptor: Int32 = -1

    private init() {}

    func acquireReplacingOtherInstances(timeout: TimeInterval = 1.5) -> Bool {
        if acquire() {
            terminateOtherInstances()
            waitForOtherInstancesToExit(until: Date().addingTimeInterval(timeout * 0.5))
            terminateOtherInstances(force: true)
            waitForOtherInstancesToExit(until: Date().addingTimeInterval(timeout * 0.5))
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
            .appendingPathComponent("\(Self.bundleIdentifier).lock")
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
                  isPeakHaloApplication(application) else {
                continue
            }

            if force {
                application.forceTerminate()
            } else {
                application.terminate()
            }
        }

        if Bundle.main.bundleIdentifier == nil {
            terminateProcessPathMatches(currentProcessID: currentProcessID, force: force)
        }
    }

    private func isPeakHaloApplication(_ application: NSRunningApplication) -> Bool {
        if Bundle.main.bundleIdentifier != nil {
            return application.bundleIdentifier == Self.bundleIdentifier
        }

        return application.executableURL?.lastPathComponent == Self.executableName
            || application.localizedName == Self.executableName
    }

    private func terminateProcessPathMatches(currentProcessID: pid_t, force: Bool) {
        let signal = force ? SIGKILL : SIGTERM

        for processID in peakHaloProcessIDs() where processID != currentProcessID {
            kill(processID, signal)
        }
    }

    private func peakHaloProcessIDs() -> [pid_t] {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return [] }

        let processCount = Int(byteCount) / MemoryLayout<pid_t>.stride
        var processIDs = Array(repeating: pid_t(0), count: processCount)
        let filledByteCount = processIDs.withUnsafeMutableBufferPointer { buffer in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.stride)
            )
        }
        guard filledByteCount > 0 else { return [] }

        return processIDs
            .prefix(Int(filledByteCount) / MemoryLayout<pid_t>.stride)
            .filter { processID in
                guard processID > 0,
                      let path = executablePath(for: processID) else {
                    return false
                }

                return URL(fileURLWithPath: path).lastPathComponent == Self.executableName
            }
    }

    private func executablePath(for processID: pid_t) -> String? {
        var buffer = Array(repeating: CChar(0), count: Int(MAXPATHLEN) * 4)
        let byteCount = buffer.withUnsafeMutableBufferPointer { buffer in
            proc_pidpath(processID, buffer.baseAddress, UInt32(buffer.count))
        }
        guard byteCount > 0 else { return nil }

        return String(cString: buffer)
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

    @discardableResult
    private func waitForOtherInstancesToExit(until deadline: Date) -> Bool {
        while Date() < deadline {
            if peakHaloProcessIDs().allSatisfy({ $0 == getpid() }) {
                return true
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        return peakHaloProcessIDs().allSatisfy { $0 == getpid() }
    }
}
