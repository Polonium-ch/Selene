import SwiftUI

/// The "Devices" detail pane: a searchable, filterable grid or list of
/// discovered hosts. Named after the file's original milestone-1 scope;
/// now embedded as a detail pane inside `ContentView`'s sidebar shell
/// rather than being the whole window.
struct DevicesView: View {
    var viewModel: HostListViewModel
    var layout: DevicesLayout
    var searchText: String
    @Binding var selectedHostID: DiscoveredHost.ID?
    var onOpenAppGrid: (DiscoveredHost) -> Void

    @State private var pairingHost: DiscoveredHost?

    private var filteredHosts: [DiscoveredHost] {
        let hosts = viewModel.hosts
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
        .sheet(item: $pairingHost) { host in
            PairingSheetView(host: host) { succeeded in
                if succeeded {
                    viewModel.refreshPairingState()
                    onOpenAppGrid(host)
                }
            }
        }
    }

    private var sectionHeader: some View {
        Text("Devices")
            .font(.title2.weight(.semibold))
    }

    private var emptyState: some View {
        Group {
            if case .failed(let message) = viewModel.state {
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 360, maximum: 360), spacing: 24)], alignment: .leading, spacing: 28) {
            ForEach(filteredHosts) { host in
                DeviceCardView(
                    host: host,
                    isSelected: selectedHostID == host.id,
                    isPaired: viewModel.isPaired(host)
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    startStream(with: host)
                }
                .onTapGesture(count: 1) {
                    selectedHostID = host.id
                }
                .contextMenu { contextMenuItems(for: host) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .contextMenu { contextMenuItems(for: host) }
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(for host: DiscoveredHost) -> some View {
        if viewModel.isPaired(host) {
            Button("Unpair", role: .destructive) {
                viewModel.unpair(host)
            }
        }
    }

    private func startStream(with host: DiscoveredHost) {
        selectedHostID = host.id

        // Paired hosts land on the app grid (Desktop/Steam Big Picture/etc,
        // with box art from /applist + /appasset) in the same window;
        // unpaired ones go through the PIN dialog first.
        if viewModel.isPaired(host) {
            onOpenAppGrid(host)
        } else {
            pairingHost = host
        }
    }
}

#Preview {
    DevicesView(
        viewModel: HostListViewModel(),
        layout: .grid,
        searchText: "",
        selectedHostID: .constant(nil),
        onOpenAppGrid: { _ in }
    )
}
