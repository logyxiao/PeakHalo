import SwiftUI

struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var metricsService: SystemMetricsService
    @ObservedObject private var preferences = DisplayPreferencesStore.shared
    @ObservedObject private var languageStore = AppLanguageStore.shared

    var body: some View {
        NotchMetricsView(
            state: viewModel.state,
            displayLayout: viewModel.displayLayout,
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
        .environment(\.locale, languageStore.locale)
    }
}
