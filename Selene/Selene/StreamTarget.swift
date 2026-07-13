import Foundation

/// The (host, app) pair identifying one streaming window - what the user
/// picked in `AppGridView`. Carried through `openWindow(value:)`, so it needs
/// the same `Codable`/`Hashable` conformances `DiscoveredHost` already has.
struct StreamTarget: Codable, Hashable {
    let host: DiscoveredHost
    let app: GameStreamApp
}
