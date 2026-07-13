import Foundation

/// Persists which Sunshine hosts we've successfully paired with, and the
/// server certificate pinned at pairing time (needed for every authenticated
/// request afterwards - applist, appasset, launch, etc). Keyed by the
/// server's own stable `<uniqueid>` from `/serverinfo`, not by mDNS name or
/// IP, mirroring how the legacy Qt client keys `NvComputer` persistence.
enum PairingStore {
    private static func key(_ serverUniqueId: String) -> String {
        "paired.\(serverUniqueId)"
    }

    static func isPaired(serverUniqueId: String) -> Bool {
        pinnedServerCertPEM(serverUniqueId: serverUniqueId) != nil
    }

    static func pinnedServerCertPEM(serverUniqueId: String) -> String? {
        UserDefaults.standard.string(forKey: key(serverUniqueId))
    }

    static func markPaired(serverUniqueId: String, serverCertPEM: String) {
        UserDefaults.standard.set(serverCertPEM, forKey: key(serverUniqueId))
    }

    static func markUnpaired(serverUniqueId: String) {
        UserDefaults.standard.removeObject(forKey: key(serverUniqueId))
    }
}
