import SwiftUI

// Favorites and Apps are coming back once they're backed by real
// functionality - for now the sidebar only offers what actually works.
enum SidebarSection: String, CaseIterable, Identifiable {
    case devices = "Devices"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .devices: "desktopcomputer"
        }
    }
}

enum DevicesLayout {
    case grid
    case list
}

struct ContentView: View {
    @State private var selection: SidebarSection? = .devices
    @State private var searchText = ""
    @State private var layout: DevicesLayout = .grid
    @State private var favoriteIDs: Set<String> = []
    @State private var selectedHostID: DiscoveredHost.ID?
    @State private var viewModel = HostListViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .badge(badgeCount(for: section))
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            // Replaced by our own fixed toolbar button below, which stays
            // anchored next to the traffic lights regardless of whether
            // the sidebar is open or closed - the automatic one moved
            // with the sidebar's own edge instead.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            DevicesView(
                viewModel: viewModel,
                layout: layout,
                searchText: searchText,
                favoriteIDs: $favoriteIDs,
                selectedHostID: $selectedHostID,
                onlyFavorites: false
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation {
                        columnVisibility = columnVisibility == .all ? .detailOnly : .all
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }

            ToolbarItem(placement: .primaryAction) {
                Picker("Layout", selection: $layout) {
                    Image(systemName: "square.grid.2x2").tag(DevicesLayout.grid)
                    Image(systemName: "list.bullet").tag(DevicesLayout.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 84)
                .help("Change how devices are displayed")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.stop()
                    viewModel.start()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Search again for devices")
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private func badgeCount(for section: SidebarSection) -> Int {
        switch section {
        case .devices:
            return viewModel.hosts.count
        }
    }
}

#Preview {
    ContentView()
}
