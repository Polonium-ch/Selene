import SwiftUI
import AppKit
import os

private let launchLogger = Logger(subsystem: "ch.polonium.selene", category: "launch")

/// The streaming session window. No actual streaming engine is wired up
/// yet (that needs `LiStartConnection` - the next milestone) - this fires
/// the `/launch` request (`GameStreamClient.launchApp`) to validate that
/// piece against real hardware, then shows the result. Opens straight into
/// native fullscreen, and otherwise behaves like any other Mac window (the
/// traffic lights can exit fullscreen, resize, close, etc. with no extra
/// code needed).
struct StreamWindowView: View {
    let host: DiscoveredHost
    let app: GameStreamApp
    var resuming: Bool = false
    /// Whatever the app grid tile already had loaded, if any - reused as a
    /// blurred backdrop behind the connecting spinner (see
    /// `ConnectingBackdrop`) instead of a flat black screen.
    var boxArtData: Data?

    @State private var errorMessage: String?
    @State private var connectionController = StreamConnectionController()
    @State private var window: NSWindow?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !connectionController.isConnected {
                ConnectingBackdrop(boxArtData: boxArtData)
                    .ignoresSafeArea()
            }

            if connectionController.isConnected {
                VideoLayerView(displayLayer: connectionController.videoRenderer.displayLayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }

            if !connectionController.isConnected {
                VStack(spacing: 20) {
                    if let boxArtData, let nsImage = NSImage(data: boxArtData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 200, height: 267)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                    }

                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("Connecting to \(app.name)…")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.white)
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                }
            }
        }
        .background(EnterFullScreenOnAppear(onResolve: { resolvedWindow in
            window = resolvedWindow
            connectionController.streamWindow = resolvedWindow
        }))
        .navigationTitle("\(app.name) — \(host.name)")
        .task {
            await attemptLaunch()
        }
        .onAppear {
            connectionController.onBackgroundRequested = {
                backgroundWindow()
            }
        }
        .onDisappear {
            if let serverUniqueId = host.serverUniqueId {
                BackgroundedSessionStore.shared.remove(serverUniqueId: serverUniqueId, appId: app.id)
            }
            connectionController.stop()
            guard let ip = host.resolvedHost, let serverUniqueId = host.serverUniqueId else { return }
            Task {
                launchLogger.notice("Cancelling session on \(ip, privacy: .public)")
                await GameStreamClient.cancelSession(ip: ip, httpsPort: SettingsStore.httpsPort, serverUniqueId: serverUniqueId)
            }
        }
    }

    // Ctrl+Option+Shift+Q (see InputForwarder) backgrounds the stream -
    // video/audio/input all keep running under the hood, and the host keeps
    // the app running because we never disconnect at all, unlike a real
    // close (traffic light/Cmd+W), which always tears down and cancels the
    // session below. Deliberately does NOT touch this window's fullscreen
    // state (exiting fullscreen broke mouse capture and left the app stuck).
    // Every fullscreen macOS app already has its own dedicated Space; simply
    // bringing a different window forward - the main Selene window here -
    // switches the display to that window's Space and leaves this one
    // running untouched in the background, exactly like switching away from
    // any other fullscreen app.
    private func backgroundWindow() {
        guard let window, let serverUniqueId = host.serverUniqueId else { return }
        BackgroundedSessionStore.shared.register(serverUniqueId: serverUniqueId, appId: app.id, window: window)

        if let mainWindow = NSApp.windows.first(where: { $0 !== window && $0.isVisible }) {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            NSApp.hide(nil)
        }
    }

    private func attemptLaunch() async {
        guard let ip = host.resolvedHost, let serverUniqueId = host.serverUniqueId else {
            errorMessage = "Missing host address"
            return
        }

        // SettingsStore.httpsPort defaults to Sunshine's standard port
        // (47984) - user-overridable in Settings > Network for hosts on a
        // non-default port. A future revision could instead carry the one
        // reported by /serverinfo when available.
        let httpsPort = SettingsStore.httpsPort
        let resolution = SettingsStore.resolution.dimensions
        let config = StreamSessionConfig.make(
            width: resolution.width,
            height: resolution.height,
            fps: SettingsStore.fps,
            bitrateKbps: SettingsStore.bitrateKbps,
            audioConfig: SettingsStore.audioConfig
        )

        // `resuming` reflects what the app grid believed when the user
        // clicked, which can be stale (e.g. right after backgrounding a
        // stream, before the grid's next /serverinfo refresh lands) -
        // sending "launch" for an app the host still has running fails with
        // "An app is already running on this host". Trust an explicit
        // Resume tap, but for a plain launch, double check the host's own
        // live state right before connecting and upgrade to a resume if it
        // turns out this app is the one already running.
        var shouldResume = resuming
        if !shouldResume {
            let liveInfo = await SunshineServerInfoFetcher.fetch(ip: ip, port: httpsPort)
            shouldResume = liveInfo?.currentGameAppId == app.id
        }

        launchLogger.notice("Launching appId=\(app.id, privacy: .public) on \(ip, privacy: .public) resuming=\(shouldResume, privacy: .public)")
        guard let sessionUrl = await GameStreamClient.launchApp(appId: app.id, resuming: shouldResume, config: config, ip: ip, httpsPort: httpsPort, serverUniqueId: serverUniqueId) else {
            launchLogger.error("Launch failed")
            errorMessage = "Launch failed"
            return
        }

        launchLogger.notice("Launch succeeded, sessionUrl0=\(sessionUrl, privacy: .public)")

        connectionController.start(
            address: ip,
            serverAppVersion: host.appVersion ?? "7.1.0.0",
            rtspSessionUrl: sessionUrl,
            config: config
        )
    }
}

/// Full-bleed blurred backdrop for the connecting screen, built from the
/// same (portrait) box art shown sharp in the foreground. Sunshine's box art
/// is always a vertical poster, so naively fitting it as a background would
/// leave big empty bars on either side - `.fill` instead scales it to cover
/// the whole window, cropping top/bottom as needed, which doesn't matter
/// once it's this blurred. Same trick Apple Music/Spotify use for portrait
/// album art behind a "now playing" screen.
private struct ConnectingBackdrop: View {
    let boxArtData: Data?

    var body: some View {
        if let boxArtData, let nsImage = NSImage(data: boxArtData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blur(radius: 60)
                .overlay(Color.black.opacity(0.55))
        }
    }
}

/// Invisible helper that reaches into AppKit to toggle the hosting
/// `NSWindow` into fullscreen once it's actually in the window hierarchy,
/// and hands that same window back via `onResolve` so the view can wire it
/// up elsewhere (background hotkey handling, input capture scoping) without
/// needing its own separate window lookup. `NSWindow` isn't `Equatable`, so
/// a plain callback is used here instead of a `Binding` + `.onChange`.
/// SwiftUI has no declarative "open this Scene already fullscreen" API on
/// macOS, so this is the standard bridge for it.
private struct EnterFullScreenOnAppear: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let hostWindow = view.window else { return }
            onResolve(hostWindow)
            guard !hostWindow.styleMask.contains(.fullScreen) else { return }
            hostWindow.toggleFullScreen(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
