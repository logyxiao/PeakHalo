import SwiftUI

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var metricsService: SystemMetricsService
    @ObservedObject private var preferences = DisplayPreferencesStore.shared

    var body: some View {
        NotchMetricsView(
            state: viewModel.state,
            metricsService: metricsService
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            NotchSurfaceShape(style: preferences.appearanceStyle)
                .fill(Color.black.opacity(0.94))
                .shadow(
                    color: .black.opacity(preferences.appearanceStyle == .dynamicIsland ? 0.36 : 0),
                    radius: 14,
                    y: 6
                )
        )
        .contentShape(NotchSurfaceShape(style: preferences.appearanceStyle))
        .onTapGesture {
            viewModel.openFromTap()
        }
        .animation(stateAnimation, value: viewModel.state)
    }

    private var stateAnimation: Animation {
        switch viewModel.state {
        case .open:
            return .spring(response: 0.42, dampingFraction: 0.82)
        case .closed:
            return .spring(response: 0.45, dampingFraction: 1.0)
        }
    }
}
