import AppKit

/// Tracks stream windows the user backgrounded via the Ctrl+Option+Shift+Q
/// hotkey (see `InputForwarder`/`StreamWindowView`) - keyed by (host, app) so
/// the app grid can offer "Continue" (bring the same still-connected window
/// back) instead of negotiating a fresh `/resume` HTTP call, which Sunshine
/// doesn't reliably support once the client has actually disconnected (its
/// `/serverinfo` currentgame field reflects "is a client connected right
/// now", not "is the app process still alive").
///
/// This is in-memory only and process-lifetime scoped - if Selene quits, any
/// backgrounded window is gone anyway, and the app grid falls back to
/// Sunshine's own `currentgame` state (a real but separate case: something
/// left running by another client or a previous run).
@MainActor
@Observable
final class BackgroundedSessionStore {
    static let shared = BackgroundedSessionStore()

    private struct Key: Hashable {
        let serverUniqueId: String
        let appId: Int
    }

    private var windows: [Key: NSWindow] = [:]

    private init() {}

    func register(serverUniqueId: String, appId: Int, window: NSWindow) {
        windows[Key(serverUniqueId: serverUniqueId, appId: appId)] = window
    }

    func window(serverUniqueId: String, appId: Int) -> NSWindow? {
        windows[Key(serverUniqueId: serverUniqueId, appId: appId)]
    }

    func remove(serverUniqueId: String, appId: Int) {
        windows.removeValue(forKey: Key(serverUniqueId: serverUniqueId, appId: appId))
    }
}
