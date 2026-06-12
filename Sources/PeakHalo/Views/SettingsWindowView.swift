import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject private var metricsService = SystemMetricsService.shared
    @State private var selectedTab: SettingsTab = .display
    @State private var searchText = ""

    private var filteredTabs: [SettingsTab] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return SettingsTab.allCases }

        return SettingsTab.allCases.filter { tab in
            String(localized: String.LocalizationValue(tab.localizationKey)).lowercased().contains(query)
                || tab.searchText.localizedCaseInsensitiveContains(query)
        }
    }

    private var resolvedSelection: SettingsTab {
        filteredTabs.contains(selectedTab) ? selectedTab : (filteredTabs.first ?? .display)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                Divider()
                    .padding(.horizontal, 12)

                List(selection: selectionBinding) {
                    Section {
                        ForEach(filteredTabs) { tab in
                            NavigationLink(value: tab) {
                                sidebarRow(for: tab)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
                .environment(\.defaultMinListRowHeight, 44)
            }
        } detail: {
            detailView(for: resolvedSelection)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .formStyle(.grouped)
        .frame(minWidth: 720, minHeight: 540)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Settings", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var selectionBinding: Binding<SettingsTab> {
        Binding(
            get: { resolvedSelection },
            set: { selectedTab = $0 }
        )
    }

    private func sidebarRow(for tab: SettingsTab) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tab.tint, tab.tint.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }

            Text(tab.title)
        }
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .display:
                Section {
                    DisplaySettingsView()
                }
            case .controls:
                Section {
                    DisplayControlsView(compact: false)
                } header: {
                    Text("Controls")
                }
            case .appearance:
                Section {
                    AppearanceSettingsView()
                }
            case .privacy:
                Section {
                    PrivacySettingsView()
                }
            case .metrics:
                Section {
                    DashboardMetricsSection(metricsService: metricsService)
                } header: {
                    Text("Metrics")
                }
            case .about:
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PeakHalo")
                            .font(.title3.weight(.semibold))
                        Text("Notch Monitor")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("About")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .padding(.top, 10)
    }
}
