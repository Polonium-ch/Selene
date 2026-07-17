import Foundation
import Observation

enum DiscoveryState: Equatable, Sendable {
    case idle
    case searching
    case failed(String)
}

@MainActor
@Observable
final class HostListViewModel {
    private(set) var hosts: [DiscoveredHost] = []
    private(set) var state: DiscoveryState = .idle
    /// `serverUniqueId`s PairingStore currently considers paired, snapshot
    /// at the last `recomputeHosts()` - an `@Observable`-tracked stand-in
    /// for `PairingStore.isPaired`, since reading UserDefaults directly
    /// inside a view's `body` isn't a dependency SwiftUI can see, so it
    /// won't re-render when pairing state changes elsewhere.
    private(set) var pairedServerIds: Set<String> = []

    private let discoveryService = HostDiscoveryService()
    private var updatesTask: Task<Void, Never>?
    private var discoveredHosts: [DiscoveredHost] = []
    private var manualHosts: [DiscoveredHost] = ManualHostStore.load()

    init() {
        recomputeHosts()
    }

    func start() {
        guard updatesTask == nil else { return }
        state = .searching

        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in self.discoveryService.updates() {
                switch update {
                case .hosts(let hosts):
                    self.discoveredHosts = hosts
                    self.recomputeHosts()
                    self.state = .searching
                case .failed(let message):
                    self.state = .failed(message)
                }
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        discoveryService.stop()
        discoveredHosts = []
        recomputeHosts()
        state = .idle
    }

    /// Adds (or replaces, if already present) a host the user typed in by
    /// IP/hostname - unlike discovered hosts, this one sticks around even
    /// when Bonjour browsing doesn't find it (VPNs, remote networks, etc).
    func addManualHost(_ host: DiscoveredHost) {
        manualHosts.removeAll { $0.id == host.id }
        manualHosts.append(host)
        ManualHostStore.save(manualHosts)
        recomputeHosts()
    }

    func removeManualHost(_ host: DiscoveredHost) {
        manualHosts.removeAll { $0.id == host.id }
        ManualHostStore.save(manualHosts)
        recomputeHosts()
    }

    func isManuallyAdded(_ host: DiscoveredHost) -> Bool {
        manualHosts.contains { $0.id == host.id }
    }

    func isPaired(_ host: DiscoveredHost) -> Bool {
        guard let serverUniqueId = host.serverUniqueId else { return false }
        return pairedServerIds.contains(serverUniqueId)
    }

    /// Clears the local pairing record for `host` - the "Unpair" context
    /// menu action. The host itself stays in the list (re-discovered via
    /// mDNS, or still present in ManualHostStore); only PairingStore's
    /// cached "we're paired" flag and pinned server cert are removed.
    func unpair(_ host: DiscoveredHost) {
        guard let serverUniqueId = host.serverUniqueId else { return }
        PairingStore.markUnpaired(serverUniqueId: serverUniqueId)
        recomputeHosts()
    }

    /// Re-derives `pairedServerIds` from PairingStore - call after any
    /// action that might change pairing state without going through
    /// `unpair()`, e.g. a `PairingSheetView` completing successfully.
    func refreshPairingState() {
        recomputeHosts()
    }

    private func recomputeHosts() {
        var seenKeys = Set<String>()
        var merged: [DiscoveredHost] = []
        for host in manualHosts + discoveredHosts {
            let key = host.serverUniqueId ?? host.id
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            merged.append(host)
        }
        hosts = merged.sorted { $0.name < $1.name }
        pairedServerIds = Set(hosts.compactMap { host in
            guard let uid = host.serverUniqueId, PairingStore.isPaired(serverUniqueId: uid) else {
                return nil
            }
            return uid
        })
    }
}
