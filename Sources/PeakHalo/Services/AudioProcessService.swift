import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

final class AudioProcessService {
    private static let systemBundlePrefixes = [
        "com.apple.siri",
        "com.apple.Siri",
        "com.apple.assistant",
        "com.apple.audio",
        "com.apple.coreaudio",
        "com.apple.mediaremote",
        "com.apple.accessibility.heard",
        "com.apple.hearingd",
        "com.apple.voicebankingd",
        "com.apple.notificationcenter",
        "com.apple.NotificationCenter",
        "com.apple.UserNotifications",
        "com.apple.usernotifications",
        "com.apple.FrontBoardServices",
        "com.apple.frontboard",
        "com.apple.springboard",
        "com.apple.SpeechRecognitionCore",
        "com.apple.speech",
        "com.apple.dictation",
        "com.apple.corespeech",
        "com.apple.CoreSpeech",
        "com.apple.VoiceControl",
        "com.apple.voicecontrol",
        "com.apple.systemsound"
    ]

    private static let systemProcessNamePrefixes = [
        "systemsoundserverd",
        "systemsoundserv",
        "coreaudiod",
        "audiomxd",
        "speechrecognitiond",
        "dictationd",
        "corespeech"
    ]

    private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t

    private var processListListenerBlock: AudioObjectPropertyListenerBlock?
    private var processListenerBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var monitoredProcesses = Set<AudioObjectID>()
    private var periodicRefreshTimer: DispatchSourceTimer?
    private var onProcessesChanged: (() -> Void)?

    deinit {
        stopMonitoring()
    }

    func startMonitoring(onChange: @escaping () -> Void) {
        onProcessesChanged = onChange
        guard processListListenerBlock == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.notifyProcessesChanged()
        }
        processListListenerBlock = block

        var address = Self.processListAddress()
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main,
            block
        )
        if status != noErr {
            processListListenerBlock = nil
        }

        updateProcessListeners(for: processObjectIDs())
        startPeriodicRefresh()
    }

    func stopMonitoring() {
        periodicRefreshTimer?.cancel()
        periodicRefreshTimer = nil

        if let block = processListListenerBlock {
            var address = Self.processListAddress()
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                .main,
                block
            )
            processListListenerBlock = nil
        }

        removeAllProcessListeners()
        onProcessesChanged = nil
    }

    func audibleProcesses() -> [AudioProcessInfo] {
        let objectIDs = processObjectIDs()
        if processListListenerBlock != nil {
            updateProcessListeners(for: objectIDs)
        }

        let runningApps = NSWorkspace.shared.runningApplications
        let runningAppsByPID = Dictionary(
            runningApps.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return objectIDs.compactMap {
            processInfo(for: $0, runningAppsByPID: runningAppsByPID)
        }
    }

    private static func processListAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func isRunningAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func startPeriodicRefresh() {
        periodicRefreshTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(10), repeating: .seconds(10))
        timer.setEventHandler { [weak self] in
            self?.notifyProcessesChanged()
        }
        periodicRefreshTimer = timer
        timer.resume()
    }

    private func notifyProcessesChanged() {
        onProcessesChanged?()
    }

    private func processObjectIDs() -> [AudioObjectID] {
        var address = Self.processListAddress()

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr,
              size > 0 else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        let status = processIDs.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return OSStatus(kAudioHardwareBadObjectError)
            }

            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                baseAddress
            )
        }

        guard status == noErr else { return [] }
        return processIDs.filter { $0 != AudioObjectID(kAudioObjectUnknown) }
    }

    private func processInfo(
        for objectID: AudioObjectID,
        runningAppsByPID: [pid_t: NSRunningApplication]
    ) -> AudioProcessInfo? {
        guard let pid = pidProperty(objectID: objectID, selector: kAudioProcessPropertyPID),
              pid > 0,
              pid != getpid() else {
            return nil
        }

        let isRunning = boolProperty(objectID: objectID, selector: kAudioProcessPropertyIsRunning) ?? false
        let isRunningOutput = boolProperty(objectID: objectID, selector: kAudioProcessPropertyIsRunningOutput) ?? false
        guard isRunning || isRunningOutput else { return nil }

        let coreAudioBundleID = stringProperty(objectID: objectID, selector: kAudioProcessPropertyBundleID)
        let directApp = runningAppsByPID[pid]
        let isRealApp = directApp?.bundleURL?.pathExtension == "app"
        let resolvedApp = isRealApp
            ? directApp
            : findResponsibleApp(for: pid, in: runningAppsByPID)
        let resolvedPID = resolvedApp?.processIdentifier ?? pid
        let isHelperBacked = resolvedPID != pid
        guard resolvedPID != getpid() else { return nil }

        let bundleIdentifier = resolvedApp?.bundleIdentifier ?? coreAudioBundleID
        let processName = resolvedApp?.localizedName
            ?? bundleIdentifier?.components(separatedBy: ".").last
            ?? processName(pid: pid)
            ?? ""
        guard !isSystemDaemon(bundleIdentifier: bundleIdentifier, processName: processName),
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }

        return AudioProcessInfo(
            objectID: objectID,
            processID: resolvedPID,
            bundleIdentifier: bundleIdentifier,
            displayName: processName.isEmpty ? nil : processName,
            icon: resolvedApp?.icon,
            isRunningOutput: isRunningOutput,
            isHelperBacked: isHelperBacked
        )
    }

    private func isSystemDaemon(bundleIdentifier: String?, processName: String) -> Bool {
        if let bundleIdentifier {
            let lowercasedBundleID = bundleIdentifier.lowercased()
            if Self.systemBundlePrefixes.contains(where: { lowercasedBundleID.hasPrefix($0.lowercased()) }) {
                return true
            }
        }

        let lowercasedName = processName.lowercased()
        return Self.systemProcessNamePrefixes.contains {
            lowercasedName.hasPrefix($0)
        }
    }

    private func findResponsibleApp(
        for pid: pid_t,
        in runningAppsByPID: [pid_t: NSRunningApplication]
    ) -> NSRunningApplication? {
        if let responsiblePID = responsiblePID(for: pid),
           let app = runningAppsByPID[responsiblePID],
           app.bundleURL?.pathExtension == "app" {
            return app
        }

        var currentPID = pid
        var visited = Set<pid_t>()

        while currentPID > 1, !visited.contains(currentPID) {
            visited.insert(currentPID)

            if let app = runningAppsByPID[currentPID],
               app.bundleURL?.pathExtension == "app" {
                return app
            }

            guard let parentPID = parentPID(for: currentPID),
                  parentPID > 0,
                  parentPID != currentPID else {
                break
            }
            currentPID = parentPID
        }

        return nil
    }

    private func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let symbol = dlsym(
            UnsafeMutableRawPointer(bitPattern: -1),
            "responsibility_get_pid_responsible_for_pid"
        ) else {
            return nil
        }

        let function = unsafeBitCast(symbol, to: ResponsibilityFunction.self)
        let responsiblePID = function(pid)
        return responsiblePID > 0 && responsiblePID != pid ? responsiblePID : nil
    }

    private func parentPID(for pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer))
            .deletingPathExtension()
            .lastPathComponent
    }

    private func updateProcessListeners(for processIDs: [AudioObjectID]) {
        let currentSet = Set(processIDs)

        for objectID in monitoredProcesses.subtracting(currentSet) {
            removeProcessListener(for: objectID)
        }

        for objectID in currentSet.subtracting(monitoredProcesses) {
            addProcessListener(for: objectID)
        }

        monitoredProcesses = currentSet
    }

    private func addProcessListener(for objectID: AudioObjectID) {
        guard processListenerBlocks[objectID] == nil else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.notifyProcessesChanged()
        }
        var address = Self.isRunningAddress()
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block)
        if status == noErr {
            processListenerBlocks[objectID] = block
        }
    }

    private func removeProcessListener(for objectID: AudioObjectID) {
        guard let block = processListenerBlocks.removeValue(forKey: objectID) else { return }
        var address = Self.isRunningAddress()
        let status = AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
        if status != noErr && status != OSStatus(kAudioHardwareBadObjectError) {
            return
        }
    }

    private func removeAllProcessListeners() {
        for objectID in monitoredProcesses {
            removeProcessListener(for: objectID)
        }
        monitoredProcesses.removeAll()
        processListenerBlocks.removeAll()
    }

    private func pidProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> pid_t? {
        var value = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return value
    }

    private func boolProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> Bool? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return value != 0
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { pointer in
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &size,
                UnsafeMutableRawPointer(pointer)
            )
        }

        guard status == noErr, let unmanaged else { return nil }
        return unmanaged.takeRetainedValue() as String
    }
}
