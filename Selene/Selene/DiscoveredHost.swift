import Foundation

/// A Sunshine/GameStream host discovered on the local network via Bonjour.
///
/// `txtRecord` is captured for visibility/debugging only - the existing Qt
/// client never reads Bonjour TXT attributes either; real host metadata
/// comes from the HTTP `/serverinfo` endpoint in a later milestone.
struct DiscoveredHost: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    var resolvedHost: String?
    var port: UInt16?
    var txtRecord: [String: String]
    var lastUpdated: Date
}
