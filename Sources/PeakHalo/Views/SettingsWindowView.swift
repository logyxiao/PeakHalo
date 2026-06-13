import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject private var languageStore = AppLanguageStore.shared
    @State private var selectedTab: SettingsTab = .display
    @State private var searchText = ""

    private var filteredTabs: [SettingsTab] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return SettingsTab.allCases }

        return SettingsTab.allCases.filter { tab in
            languageStore.localizedString(tab.localizationKey).lowercased().contains(query)
                || tab.searchText.localizedCaseInsensitiveContains(query)
        }
    }

    private var resolvedSelection: SettingsTab {
        filteredTabs.contains(selectedTab) ? selectedTab : (filteredTabs.first ?? .display)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(filteredTabs) { tab in
                    NavigationLink(value: tab) {
                        sidebarRow(for: tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
            .environment(\.defaultMinListRowHeight, 40)
            .searchable(
                text: $searchText,
                placement: .sidebar,
                prompt: Text(languageStore.localizedString("Search Settings"))
            )
        } detail: {
            detailView(for: resolvedSelection)
                .navigationTitle(languageStore.localizedString(resolvedSelection.localizationKey))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.locale, languageStore.locale)
        .id(languageStore.language.rawValue)
        .frame(minWidth: 720, minHeight: 540)
    }

    private var selectionBinding: Binding<SettingsTab> {
        Binding(
            get: { resolvedSelection },
            set: { selectedTab = $0 }
        )
    }

    private func sidebarRow(for tab: SettingsTab) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tab.tint, tab.tint.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }

            Text(languageStore.localizedString(tab.localizationKey))
                .font(.body)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .display:
            DisplaySettingsView()
        case .controls:
            DisplayControlsView(compact: false)
        case .permissions:
            PermissionsSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}
