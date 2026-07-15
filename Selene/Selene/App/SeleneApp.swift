import SwiftUI

@main
struct SeleneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1170, height: 400)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }
        }

        WindowGroup(for: StreamTarget.self) { $target in
            if let target {
                StreamWindowView(host: target.host, app: target.app, resuming: target.resuming)
            }
        }
        .defaultSize(width: 1280, height: 720)
    }
}
