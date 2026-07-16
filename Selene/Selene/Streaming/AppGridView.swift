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
    // The app ID Sunshine reports as currently running (0/absent = nothing) -
    // drives the "Resume"/"Stop" overlay, mirroring the legacy Qt client's
    // AppView.qml (`model.running`), which reads this off /serverinfo rather
    // than tracking it purely client-side, so it stays correct even if this
    // app was relaunched or another client disconnected/reconnected.
    private(set) var runningAppId: Int?

    private let host: DiscoveredHost

    // Defaults to Sunshine's standard HTTPS port, user-overridable in
    // Settings > Network. A future revision could instead carry the one
    // reported by /serverinfo (SunshineServerInfo.httpsPort) when available.
    private let httpsPort: UInt16 = SettingsStore.httpsPort

    init(host: DiscoveredHost) {
        self.host = host
    }

    func load() async {
        guard let ip = host.resolvedHost, let serverUniqueId = host.serverUniqueId else {
            errorMessage = "Missing host address."
            isLoading = false
            return
        }

        guard let fetchedApps = await GameStreamClient.fetchAppList(ip: ip, httpsPort: httpsPort, serverUniqueId: serverUniqueId) else {
            errorMessage = "Couldn't load the app list from this PC."
            isLoading = false
            return
        }

        apps = fetchedApps.map { AppGridEntry(app: $0, boxArtData: nil) }
        isLoading = false

        await refreshRunningState()

        for app in fetchedApps {
            let data = await GameStreamClient.fetchBoxArt(appId: app.id, ip: ip, httpsPort: httpsPort, serverUniqueId: serverUniqueId)
            guard let data, let index = apps.firstIndex(where: { $0.id == app.id }) else { continue }
            apps[index].boxArtData = data
        }
    }

    /// Cheap re-check of just /serverinfo's currentgame - called when the
    /// app regains focus (e.g. after backgrounding a stream) so the
    /// Resume/Stop overlay stays accurate without redoing the full app
    /// list/box art fetch.
    func refreshRunningState() async {
        guard let ip = host.resolvedHost else { return }
        let info = await SunshineServerInfoFetcher.fetch(ip: ip, port: httpsPort)
        runningAppId = info?.currentGameAppId
    }

    func stopRunningApp() async {
        guard let ip = host.resolvedHost, let serverUniqueId = host.serverUniqueId else { return }
        _ = await GameStreamClient.cancelSession(ip: ip, httpsPort: httpsPort, serverUniqueId: serverUniqueId)
        runningAppId = nil
    }
}

/// The app-selection grid shown after connecting to a paired host - what the
/// real Moonlight/Sunshine flow shows before actually streaming anything
/// (Desktop, Steam Big Picture, individual games, each with box art pulled
/// from the host itself via `/applist` + `/appasset`). Mirrors `AppView.qml`
/// in the legacy Qt client.
struct AppGridView: View {
    let host: DiscoveredHost
    /// `resuming: true` calls Sunshine's `/resume` instead of `/launch` -
    /// only ever set for the tile matching `runningAppId`. `boxArtData` is
    /// whatever this tile already has loaded, if any, passed through so the
    /// connecting screen doesn't have to re-fetch it.
    var onSelectApp: (GameStreamApp, _ resuming: Bool, _ boxArtData: Data?) -> Void

    @State private var viewModel: AppGridViewModel
    // Finder-style selection: a single click just marks a tile selected (shows
    // the ring below); a second click (recognized as a double-tap) is what
    // actually connects.
    @State private var selectedAppId: Int?

    init(host: DiscoveredHost, onSelectApp: @escaping (GameStreamApp, _ resuming: Bool, _ boxArtData: Data?) -> Void) {
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
                                let backgroundedWindow = host.serverUniqueId.flatMap {
                                    BackgroundedSessionStore.shared.window(serverUniqueId: $0, appId: entry.app.id)
                                }
                                let isRunning = backgroundedWindow != nil || entry.app.id == viewModel.runningAppId
                                AppTileView(
                                    entry: entry,
                                    isRunning: isRunning,
                                    isSelected: selectedAppId == entry.app.id,
                                    onResume: {
                                        // A window we backgrounded ourselves is still fully
                                        // connected - just bring it back, no network round trip.
                                        // Otherwise fall back to Sunshine's own /resume, for an
                                        // app left running by another client or a previous run.
                                        if let backgroundedWindow {
                                            // The window was never miniaturized/exited fullscreen
                                            // (see StreamWindowView.backgroundWindow) - bringing it
                                            // forward switches back to its own Space, same as
                                            // switching to any other fullscreen app.
                                            backgroundedWindow.makeKeyAndOrderFront(nil)
                                        } else {
                                            onSelectApp(entry.app, true, entry.boxArtData)
                                        }
                                    },
                                    onStop: {
                                        if let backgroundedWindow {
                                            // Goes through the window's own .onDisappear, which
                                            // already tears down the connection and cancels the
                                            // session - no need to duplicate that here.
                                            backgroundedWindow.close()
                                        } else {
                                            Task { await viewModel.stopRunningApp() }
                                        }
                                    }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    // Matches the legacy client: a different
                                    // app can't be launched while one is
                                    // already running - Stop it from its own
                                    // tile first.
                                    guard !isRunning else { return }
                                    onSelectApp(entry.app, false, entry.boxArtData)
                                }
                                .onTapGesture(count: 1) {
                                    selectedAppId = entry.app.id
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await viewModel.refreshRunningState() }
        }
    }
}

private struct AppTileView: View {
    fileprivate let entry: AppGridEntry
    let isRunning: Bool
    let isSelected: Bool
    let onResume: () -> Void
    let onStop: () -> Void

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

                if isRunning {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.55))
                    VStack(spacing: 10) {
                        Button(action: onResume) {
                            Label("Resume", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button(action: onStop) {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .frame(width: 200, height: 267)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isRunning || isSelected {
                    // Matches DeviceCardView's selection ring styling, so
                    // "this is selected/running" reads consistently with
                    // "this is connected" elsewhere in the app.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                }
            }

            Text(entry.app.name)
                .font(.callout)
                .lineLimit(1)
        }
    }
}
