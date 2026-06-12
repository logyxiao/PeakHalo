import SwiftUI

struct ContentView: View {
    @ObservedObject var metricsService: SystemMetricsService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                DashboardMetricsSection(metricsService: metricsService)

                VStack(alignment: .leading, spacing: 16) {
                    DisplaySettingsView()
                    Divider()
                    AppearanceSettingsView()
                    Divider()
                    PrivacySettingsView()
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                footer
            }
            .padding(22)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PeakHalo")
                    .font(.title2.weight(.semibold))
                Text("Notch Monitor")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Open Notch") {
                    NotchWindowManager.shared.open()
                }
                Button("Collapse") {
                    NotchWindowManager.shared.close()
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "Updated %@"),
                    MetricFormat.time(metricsService.snapshot.updatedAt)
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit PeakHalo") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
