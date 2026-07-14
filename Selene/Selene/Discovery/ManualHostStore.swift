import Foundation

/// Persists hosts the user added manually by IP/hostname (for remote
/// streaming over a VPN, or networks where Bonjour/mDNS doesn't reach) -
/// unlike discovered hosts, these don't disappear when Bonjour browsing
/// stops finding them.
enum ManualHostStore {
    private static let key = "manualHosts"

    static func load() -> [DiscoveredHost] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let hosts = try? JSONDecoder().decode([DiscoveredHost].self, from: data) else {
            return []
        }
        return hosts
    }

    static func save(_ hosts: [DiscoveredHost]) {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
