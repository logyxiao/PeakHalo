import Foundation

@MainActor
final class BatteryDeviceStore: NSObject, ObservableObject {
    static let shared = BatteryDeviceStore()

    @Published private(set) var devices: [BatteryDevice] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastMessage: String?

    private let service = BatteryDeviceService()
    private let worker = BatteryDeviceWorker()
    private var hasLoaded = false
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 60

    private override init() {
        super.init()
    }

    func refreshIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func startMonitoring() {
        refreshIfNeeded()
        guard refreshTimer == nil else { return }

        refreshTimer = Timer.scheduledTimer(
            timeInterval: refreshInterval,
            target: self,
            selector: #selector(refreshTimerDidFire(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        worker.refresh(service: service) { devices in
            Task { @MainActor in
                BatteryDeviceStore.shared.applyRefresh(devices)
            }
        }
    }

    @objc private func refreshTimerDidFire(_ timer: Timer) {
        refresh()
    }

    private func applyRefresh(_ devices: [BatteryDevice]) {
        hasLoaded = true
        self.devices = devices
        isRefreshing = false
        lastMessage = devices.isEmpty ? String(localized: "No battery devices found.") : nil
    }
}

private final class BatteryDeviceWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.peakhalo.battery-devices", qos: .utility)

    func refresh(service: BatteryDeviceService, completion: @Sendable @escaping ([BatteryDevice]) -> Void) {
        queue.async {
            completion(service.devices())
        }
    }
}
