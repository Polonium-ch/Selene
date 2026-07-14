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
    }
}
