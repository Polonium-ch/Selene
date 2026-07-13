import SwiftUI
import AppKit

/// The streaming session window. No actual streaming engine is wired up
/// yet (that needs the Session/moonlight-common-c bridge to the legacy
/// Qt/SDL/FFmpeg engine - a future milestone) - this is the window
/// shell/interaction pattern: opens straight into native fullscreen, and
/// otherwise behaves like any other Mac window (the traffic lights can
/// exit fullscreen, resize, close, etc. with no extra code needed).
struct StreamWindowView: View {
    let host: DiscoveredHost

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text("Connecting to \(host.name)…")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white)
                if let resolvedHost = host.resolvedHost {
                    Text(resolvedHost)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .background(EnterFullScreenOnAppear())
        .navigationTitle(host.name)
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
