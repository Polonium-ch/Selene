import SwiftUI

/// An app entry paired with its (lazily loaded) box art, for `AppGridView`.
private struct AppGridEntry: Identifiable, Hashable {
    let app: GameStreamApp
    var boxArtData: Data?

    var id: Int { app.id }
}

@MainActor
@Observable
private final class AppGridViewModel {
    private(set) var apps: [AppGridEntry] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?

    private let host: DiscoveredHost

    init(host: DiscoveredHost) {
        self.host = host
    }

    func load() async {
        guard let ip = host.resolvedHost, let serverUniqueId = host.serverUniqueId else {
            errorMessage = "Missing host address."
            isLoading = false
            return
        }

        // Sunshine's default HTTPS port. A future revision should carry the
        // one reported by /serverinfo (SunshineServerInfo.httpsPort) instead
        // of assuming the default here.
        let httpsPort: UInt16 = 47984

        guard let fetchedApps = await GameStreamClient.fetchAppList(ip: ip, httpsPort: httpsPort, serverUniqueId: serverUniqueId) else {
            errorMessage = "Couldn't load the app list from this PC."
            isLoading = false
            return
        }

        apps = fetchedApps.map { AppGridEntry(app: $0, boxArtData: nil) }
        isLoading = false

        for app in fetchedApps {
            let data = await GameStreamClient.fetchBoxArt(appId: app.id, ip: ip, httpsPort: httpsPort, serverUniqueId: serverUniqueId)
            guard let data, let index = apps.firstIndex(where: { $0.id == app.id }) else { continue }
            apps[index].boxArtData = data
        }
    }
}

/// The app-selection grid shown after connecting to a paired host - what the
/// real Moonlight/Sunshine flow shows before actually streaming anything
/// (Desktop, Steam Big Picture, individual games, each with box art pulled
/// from the host itself via `/applist` + `/appasset`). Mirrors `AppView.qml`
/// in the legacy Qt client.
struct AppGridView: View {
    let host: DiscoveredHost
    var onSelectApp: (GameStreamApp) -> Void

    @State private var viewModel: AppGridViewModel

    init(host: DiscoveredHost, onSelectApp: @escaping (GameStreamApp) -> Void) {
        self.host = host
        self.onSelectApp = onSelectApp
        _viewModel = State(initialValue: AppGridViewModel(host: host))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(host.name)
                .font(.title2.weight(.semibold))
                .padding([.top, .horizontal], 20)

            Group {
                if viewModel.isLoading {
                    ProgressView("Loading apps…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't Load Apps", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 200), spacing: 20)], alignment: .leading, spacing: 20) {
                            ForEach(viewModel.apps) { entry in
                                AppTileView(entry: entry)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) {
                                        onSelectApp(entry.app)
                                    }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .navigationTitle(host.name)
        .task {
            await viewModel.load()
        }
    }
}

private struct AppTileView: View {
    fileprivate let entry: AppGridEntry

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.gray.opacity(0.2))

                if let data = entry.boxArtData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 267)

            Text(entry.app.name)
                .font(.callout)
                .lineLimit(1)
        }
    }
}
