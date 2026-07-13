import SwiftUI
import AppKit
import os

private let launchLogger = Logger(subsystem: "ch.useselene.selene", category: "launch")

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

    @State private var statusText = "Connecting…"
    @State private var connectionController = StreamConnectionController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if connectionController.isConnected {
                VideoLayerView(displayLayer: connectionController.videoRenderer.displayLayer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
            }

            if !connectionController.isConnected {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text("Connecting to \(app.name)…")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white)
                    if let resolvedHost = host.resolvedHost {
                        Text(resolvedHost)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    ForEach(Array(connectionController.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .background(EnterFullScreenOnAppear())
        .navigationTitle("\(app.name) — \(host.name)")
        .task {
            await attemptLaunch()
        }
        .onDisappear {
            connectionController.stop()
            guard let ip = host.resolvedHost, let serverUniqueId = host.serverUniqueId else { return }
            Task {
                launchLogger.notice("Cancelling session on \(ip, privacy: .public)")
                await GameStreamClient.cancelSession(ip: ip, httpsPort: 47984, serverUniqueId: serverUniqueId)
            }
        }
    }

    private func attemptLaunch() async {
        guard let ip = host.resolvedHost, let serverUniqueId = host.serverUniqueId else {
            statusText = "Missing host address"
            return
        }

        // Sunshine's default HTTPS port. A future revision should carry the
        // one reported by /serverinfo instead of assuming the default here.
        let httpsPort: UInt16 = 47984
        let config = StreamSessionConfig.make()

        launchLogger.notice("Launching appId=\(app.id, privacy: .public) on \(ip, privacy: .public)")
        guard let sessionUrl = await GameStreamClient.launchApp(appId: app.id, resuming: false, config: config, ip: ip, httpsPort: httpsPort, serverUniqueId: serverUniqueId) else {
            launchLogger.error("Launch failed")
            statusText = "Launch failed"
            return
        }

        launchLogger.notice("Launch succeeded, sessionUrl0=\(sessionUrl, privacy: .public)")
        statusText = "Launch succeeded, connecting session…"

        connectionController.start(
            address: ip,
            serverAppVersion: host.appVersion ?? "7.1.0.0",
            rtspSessionUrl: sessionUrl,
            config: config
        )
    }
}

/// Invisible helper that reaches into AppKit to toggle the hosting
/// `NSWindow` into fullscreen once it's actually in the window hierarchy.
/// SwiftUI has no declarative "open this Scene already fullscreen" API on
/// macOS, so this is the standard bridge for it.
private struct EnterFullScreenOnAppear: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window, !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
