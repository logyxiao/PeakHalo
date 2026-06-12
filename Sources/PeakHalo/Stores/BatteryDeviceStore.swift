import Foundation

@MainActor
final class BatteryDeviceStore: ObservableObject {
    static let shared = BatteryDeviceStore()

    @Published private(set) var devices: [BatteryDevice] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastMessage: String?

    private let service = BatteryDeviceService()
    private let worker = BatteryDeviceWorker()
    private var hasLoaded = false
    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 60

    private init() {}

    func refreshIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func startMonitoring() {
        refreshIfNeeded()
        guard refreshTimer == nil else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        worker.refresh(service: service) { [weak self] devices in
            Task { @MainActor in
                self?.hasLoaded = true
                self?.devices = devices
                self?.isRefreshing = false
                self?.lastMessage = devices.isEmpty ? String(localized: "No battery devices found.") : nil
            }
        }
    }
}

private final class BatteryDeviceWorker {
    private let queue = DispatchQueue(label: "com.peakhalo.battery-devices", qos: .utility)

    func refresh(service: BatteryDeviceService, completion: @escaping ([BatteryDevice]) -> Void) {
        queue.async {
            completion(service.devices())
        }
    }
}
