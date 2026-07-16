import SwiftUI

@main
struct SeleneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1170, height: 400)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Selene") {
                    openWindow(id: "about")
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }
        }

        WindowGroup(for: StreamTarget.self) { $target in
            if let target {
                StreamWindowView(host: target.host, app: target.app, resuming: target.resuming, boxArtData: target.boxArtData)
            }
        }
        .defaultSize(width: 1280, height: 720)

        Window("About Selene", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
        }
    }
}
