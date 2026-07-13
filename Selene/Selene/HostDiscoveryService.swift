import Foundation
import Network
import os

private let discoveryLogger = Logger(subsystem: "ch.useselene.selene", category: "discovery")

/// An update yielded by `HostDiscoveryService.updates()`.
enum DiscoveryUpdate: Sendable {
    case hosts([DiscoveredHost])
    case failed(String)
}

/// Thin wrapper around `NWBrowser` that discovers Sunshine/GameStream hosts
/// advertising `_nvstream._tcp` on the local network and resolves each one
/// to a real IP/port.
///
/// Mirrors the mDNS service type the existing Qt client uses
/// (`computermanager.cpp`: `"_nvstream._tcp.local."`), via Apple's native
/// Bonjour APIs instead of the vendored qmdnsengine.
@MainActor
final class HostDiscoveryService {
    static let serviceType = "_nvstream._tcp"

    private var browser: NWBrowser?
    private var resolved: [NWEndpoint: DiscoveredHost] = [:]
    private var continuation: AsyncStream<DiscoveryUpdate>.Continuation?

    /// Starts browsing and returns a stream of host-list/failure updates.
    /// Browsing stops automatically when the stream's consumer stops
    /// iterating (e.g. the owning view disappears).
    func updates() -> AsyncStream<DiscoveryUpdate> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.startBrowsing()

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.stop()
                }
            }
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolved.removeAll()
    }

    private func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = false

        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            guard case .failed(let error) = state else { return }
            Task { @MainActor in
                self?.continuation?.yield(.failed("\(error)"))
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            discoveryLogger.notice("browseResultsChanged: \(results.count, privacy: .public) result(s)")
            Task { @MainActor in
                await self?.reconcile(results: results)
            }
        }

        browser.start(queue: .global(qos: .userInitiated))
        discoveryLogger.notice("browser.start() called")
        self.browser = browser
    }

    /// Resolves any newly-seen results and drops ones no longer advertised,
    /// then publishes the current host list.
    private func reconcile(results: Set<NWBrowser.Result>) async {
        let currentEndpoints = Set(results.map(\.endpoint))
        resolved = resolved.filter { currentEndpoints.contains($0.key) }

        await withTaskGroup(of: (NWEndpoint, DiscoveredHost)?.self) { group in
            for result in results where resolved[result.endpoint] == nil {
                group.addTask { [weak self] in
                    guard let self, case let .service(name, _, _, _) = result.endpoint else {
                        discoveryLogger.notice("skip: endpoint isn't .service")
                        return nil
                    }
                    discoveryLogger.notice("resolving endpoint for \(name, privacy: .public)")
                    guard let (host, port) = await self.resolve(endpoint: result.endpoint) else {
                        discoveryLogger.notice("resolve FAILED for \(name, privacy: .public)")
                        return nil
                    }
                    discoveryLogger.notice("resolved \(name, privacy: .public) -> \(host, privacy: .public):\(port, privacy: .public)")

                    var txt: [String: String] = [:]
                    if case let .bonjour(record) = result.metadata {
                        txt = record.dictionary
                    }

                    // The Bonjour instance name isn't the user-configured "Sunshine
                    // Name" - fetch the real one from /serverinfo, same as the
                    // legacy Qt client does. Falls back to the Bonjour name if the
                    // host doesn't respond (offline, firewalled, etc).
                    let serverInfo = await SunshineServerInfoFetcher.fetch(ip: host, port: port)
                    discoveryLogger.notice("serverinfo for \(name, privacy: .public): hostname=\(serverInfo?.hostname ?? "nil", privacy: .public) uniqueId=\(serverInfo?.uniqueId ?? "nil", privacy: .public)")

                    let discovered = DiscoveredHost(
                        id: name,
                        name: serverInfo?.hostname ?? name,
                        resolvedHost: host,
                        port: port,
                        txtRecord: txt,
                        lastUpdated: Date(),
                        serverUniqueId: serverInfo?.uniqueId,
                        appVersion: serverInfo?.appVersion
                    )
                    return (result.endpoint, discovered)
                }
            }

            for await entry in group {
                guard let (endpoint, host) = entry else { continue }
                resolved[endpoint] = host
            }
        }

        discoveryLogger.notice("yielding \(self.resolved.count, privacy: .public) host(s)")
        continuation?.yield(.hosts(resolved.values.sorted { $0.name < $1.name }))
    }

    /// Opens a transient TCP connection purely to resolve `endpoint` to a
    /// concrete IP/port (NWBrowser results carry a Bonjour service identity,
    /// not a resolved address). Expected port for `_nvstream._tcp` is 47989.
    private func resolve(endpoint: NWEndpoint) async -> (host: String, port: UInt16)? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let resumeGuard = ResumeGuard()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeGuard.tryResume() else { return }
                    if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                        // NWEndpoint.Host's string form appends a "%en0"-style
                        // zone/interface identifier - useful for actually
                        // connecting to link-local addresses, but not
                        // something a user needs to see.
                        let displayHost = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
                        continuation.resume(returning: (displayHost, port.rawValue))
                    } else {
                        continuation.resume(returning: nil)
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    guard resumeGuard.tryResume() else { return }
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
        }
    }
}

/// Guards a `CheckedContinuation` against being resumed more than once from
/// `NWConnection`'s serially-delivered but non-actor-isolated state callback.
private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}
