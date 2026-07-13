import SwiftUI

@main
struct SeleneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1170, height: 400)

        WindowGroup(for: StreamTarget.self) { $target in
            if let target {
                StreamWindowView(host: target.host, app: target.app)
            }
        }
        .defaultSize(width: 1280, height: 720)
    }
}
