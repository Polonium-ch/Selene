import SwiftUI

@main
struct SeleneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        WindowGroup(for: DiscoveredHost.self) { $host in
            if let host {
                StreamWindowView(host: host)
            }
        }
        .defaultSize(width: 1280, height: 720)
    }
}
