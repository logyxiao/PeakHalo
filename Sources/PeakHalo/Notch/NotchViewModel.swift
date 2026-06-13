import Foundation

@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var state: NotchState = .closed
    @Published private(set) var displayLayout = NotchDisplayLayout.none
    @Published var isHovering = false

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private let hoverOpenDelay: Duration = .milliseconds(140)
    private let hoverCloseDelay: Duration = .milliseconds(260)

    func open() {
        openTask?.cancel()
        closeTask?.cancel()
        guard state != .open else { return }
        state = .open
    }

    func close() {
        openTask?.cancel()
        closeTask?.cancel()
        guard state != .closed else { return }
        state = .closed
    }

    func openFromTap() {
        if state == .closed {
            open()
        }
    }

    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering

        if hovering {
            scheduleOpen()
        } else {
            scheduleClose()
        }
    }

    func updateDisplayLayout(_ layout: NotchDisplayLayout) {
        guard displayLayout != layout else { return }
        displayLayout = layout
    }

    private func scheduleOpen() {
        closeTask?.cancel()
        guard state == .closed else { return }

        openTask?.cancel()
        let delay = hoverOpenDelay
        openTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            await MainActor.run {
                guard let self, self.isHovering, self.state == .closed else { return }
                self.state = .open
            }
        }
    }

    private func scheduleClose() {
        openTask?.cancel()
        guard state == .open else { return }

        closeTask?.cancel()
        let delay = hoverCloseDelay
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            await MainActor.run {
                guard let self, !self.isHovering else { return }
                self.state = .closed
            }
        }
    }
}
