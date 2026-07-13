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

    func start() {
        guard updatesTask == nil else { return }
        state = .searching

        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in self.discoveryService.updates() {
                switch update {
                case .hosts(let hosts):
                    self.hosts = hosts
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
        hosts = []
        state = .idle
    }
}
