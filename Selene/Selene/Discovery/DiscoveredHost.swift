import Foundation

/// A Sunshine/GameStream host discovered on the local network via Bonjour.
///
/// `txtRecord` is captured for visibility/debugging only - the existing Qt
/// client never reads Bonjour TXT attributes either; real host metadata
/// comes from the HTTP `/serverinfo` endpoint (`SunshineServerInfoFetcher`).
struct DiscoveredHost: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    var resolvedHost: String?
    var port: UInt16?
    var txtRecord: [String: String]
    var lastUpdated: Date

    /// The host's own stable identity from `/serverinfo`'s `<uniqueid>` -
    /// unlike `id` (the Bonjour instance name) or `resolvedHost` (an IP that
    /// can change with DHCP), this is the right key for persisting "have we
    /// paired with this host" (mirrors `NvComputer`'s persistence key in the
    /// legacy Qt client).
    var serverUniqueId: String?

    /// The host's GameStream/Sunshine protocol version from `<appversion>` -
    /// determines which hash algorithm the pairing handshake must use
    /// (`GameStreamPairing`).
    var appVersion: String?
}
