import SwiftUI

/// The "Devices" detail pane: a searchable, filterable grid or list of
/// discovered hosts. Named after the file's original milestone-1 scope;
/// now embedded as a detail pane inside `ContentView`'s sidebar shell
/// rather than being the whole window.
struct DevicesView: View {
    var viewModel: HostListViewModel
    var layout: DevicesLayout
    var searchText: String
    @Binding var favoriteIDs: Set<String>
    @Binding var selectedHostID: DiscoveredHost.ID?
    var onlyFavorites: Bool

    @Environment(\.openWindow) private var openWindow

    private var filteredHosts: [DiscoveredHost] {
        var hosts = viewModel.hosts
        if onlyFavorites {
            hosts = hosts.filter { favoriteIDs.contains($0.id) }
        }
        guard !searchText.isEmpty else { return hosts }
        return hosts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader

                if filteredHosts.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if layout == .grid {
                    grid
                } else {
                    list
                }
            }
            .padding(20)
        }
        .background(.background)
        .task {
            viewModel.start()
        }
    }

    private var sectionHeader: some View {
        Text(onlyFavorites ? "Favorite Devices" : "Devices")
            .font(.title2.weight(.semibold))
    }

    private var emptyState: some View {
        Group {
            if onlyFavorites {
                ContentUnavailableView {
                    Label("No Favorites Yet", systemImage: "star")
                } description: {
                    Text("Star a device to add it here.")
                }
            } else if case .failed(let message) = viewModel.state {
                ContentUnavailableView {
                    Label("Discovery Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            } else {
                ContentUnavailableView {
                    Label("Searching for Devices…", systemImage: "network")
                } description: {
                    Text("Looking for Sunshine or GameStream PCs on your local network.")
                }
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 24)], spacing: 28) {
            ForEach(filteredHosts) { host in
                DeviceCardView(
                    host: host,
                    isFavorite: favoriteBinding(for: host),
                    isSelected: selectedHostID == host.id
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    startStream(with: host)
                }
                .onTapGesture(count: 1) {
                    selectedHostID = host.id
                }
            }
        }
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(filteredHosts) { host in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DeviceCardView.tint(for: host).gradient)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(host.name)
                            .font(.body)
                        if let resolvedHost = host.resolvedHost {
                            Text(resolvedHost)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    let isFavorite = favoriteBinding(for: host)
                    Button {
                        isFavorite.wrappedValue.toggle()
                    } label: {
                        Image(systemName: isFavorite.wrappedValue ? "star.fill" : "star")
                            .foregroundStyle(isFavorite.wrappedValue ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selectedHostID == host.id ? Color.accentColor.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    startStream(with: host)
                }
                .onTapGesture(count: 1) {
                    selectedHostID = host.id
                }
            }
        }
    }

    private func startStream(with host: DiscoveredHost) {
        selectedHostID = host.id
        openWindow(value: host)
    }

    private func favoriteBinding(for host: DiscoveredHost) -> Binding<Bool> {
        Binding(
            get: { favoriteIDs.contains(host.id) },
            set: { isFavorite in
                if isFavorite {
                    favoriteIDs.insert(host.id)
                } else {
                    favoriteIDs.remove(host.id)
                }
            }
        )
    }
}

#Preview {
    DevicesView(
        viewModel: HostListViewModel(),
        layout: .grid,
        searchText: "",
        favoriteIDs: .constant([]),
        selectedHostID: .constant(nil),
        onlyFavorites: false
    )
}
