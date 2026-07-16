import SwiftUI
import AppKit

/// A custom "About Selene" window, replacing the generic default AppKit
/// panel (which had no copyright/credits configured at all - see
/// `Info.plist`) - opened via `SeleneApp`'s `CommandGroup(replacing: .appInfo)`.
struct AboutView: View {
    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("Selene")
                    .font(.title.weight(.semibold))
                Text("Version \(shortVersion) (\(buildNumber))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("A native macOS client for Sunshine & NVIDIA GameStream.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 260)

            HStack(spacing: 20) {
                Link("GitHub", destination: URL(string: "https://github.com/Polonium-ch/Selene")!)
                Link("License", destination: URL(string: "https://github.com/Polonium-ch/Selene/blob/main/LICENSE")!)
            }
            .font(.callout)

            Divider()
                .frame(width: 260)

            VStack(spacing: 6) {
                Text("ACKNOWLEDGEMENTS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)

                acknowledgement(name: "moonlight-common-c", role: "GameStream protocol engine", url: "https://github.com/moonlight-stream/moonlight-common-c")
                acknowledgement(name: "Sparkle", role: "Software updates", url: "https://github.com/sparkle-project/Sparkle")
            }

            Text("© 2026 Polonium. Licensed under GPLv3.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .background(ConfigureAboutWindow())
    }

    private func acknowledgement(name: String, role: String, url: String) -> some View {
        HStack(spacing: 4) {
            Link(name, destination: URL(string: url)!)
            Text("— \(role)")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

/// Strips this window down to look like a genuine macOS About panel - no
/// title text, no minimize/zoom, fixed size - rather than a regular document
/// window that happens to be small. Same AppKit-bridging trick
/// `StreamWindowView`'s `EnterFullScreenOnAppear` already uses in this
/// codebase for the same reason (SwiftUI's `Window` scene has no
/// declarative API for this level of chrome control).
private struct ConfigureAboutWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.styleMask.remove([.miniaturizable, .resizable])
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    AboutView()
}
