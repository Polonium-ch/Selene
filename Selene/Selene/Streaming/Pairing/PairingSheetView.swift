import SwiftUI

/// Drives one pairing attempt: generates the 4-digit PIN (matching the
/// legacy Qt client's `ComputerManager::generatePinString()`), runs the
/// handshake in the background, and persists the result.
@MainActor
@Observable
final class PairingViewModel {
    enum Phase: Equatable {
        case pairing(pin: String)
        case succeeded
        case failed(String)
    }

    private(set) var phase: Phase

    private let host: DiscoveredHost
    private let onFinished: (Bool) -> Void
    private var didStart = false

    init(host: DiscoveredHost, onFinished: @escaping (Bool) -> Void) {
        self.host = host
        self.onFinished = onFinished
        self.phase = .pairing(pin: String(format: "%04d", Int.random(in: 0..<10000)))
    }

    func start() {
        guard !didStart, case .pairing(let pin) = phase else { return }
        didStart = true

        guard let ip = host.resolvedHost, let httpPort = host.port else {
            phase = .failed("Missing host address.")
            return
        }

        // Defaults to Sunshine's standard HTTPS port, user-overridable in
        // Settings > Network. A future revision could instead carry the one
        // reported by /serverinfo (SunshineServerInfo.httpsPort) when available.
        let httpsPort = SettingsStore.httpsPort

        Task {
            let result = await GameStreamPairing.pair(
                ip: ip,
                httpPort: httpPort,
                httpsPort: httpsPort,
                appVersion: host.appVersion,
                pin: pin
            )

            await MainActor.run {
                switch result {
                case .paired(let serverCertPEM):
                    if let serverUniqueId = host.serverUniqueId {
                        PairingStore.markPaired(serverUniqueId: serverUniqueId, serverCertPEM: serverCertPEM)
                    }
                    phase = .succeeded
                    onFinished(true)
                case .pinWrong:
                    phase = .failed("Incorrect PIN. Try again.")
                    onFinished(false)
                case .alreadyInProgress:
                    phase = .failed("This PC is already pairing with someone else.")
                    onFinished(false)
                case .failed(let message):
                    phase = .failed(message)
                    onFinished(false)
                }
            }
        }
    }
}

/// The PIN pairing dialog: shows the generated PIN while the handshake runs
/// in the background, matching `PcView.qml`'s `pairDialog` UX in the legacy
/// Qt client (generate PIN -> kick off pairing -> show PIN -> wait).
struct PairingSheetView: View {
    @State private var viewModel: PairingViewModel
    @Environment(\.dismiss) private var dismiss

    init(host: DiscoveredHost, onFinished: @escaping (Bool) -> Void) {
        _viewModel = State(initialValue: PairingViewModel(host: host, onFinished: onFinished))
    }

    var body: some View {
        VStack(spacing: 20) {
            switch viewModel.phase {
            case .pairing(let pin):
                ProgressView()
                Text("Enter this PIN on your Sunshine PC")
                    .font(.headline)
                Text(pin)
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .kerning(6)
                Text("Open Sunshine's web UI, go to PIN pairing, and type this code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Paired!")
                    .font(.headline)

            case .failed(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }

            Button(isTerminal ? "Done" : "Cancel") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 340)
        .task {
            viewModel.start()
        }
    }

    private var isTerminal: Bool {
        if case .pairing = viewModel.phase {
            return false
        }
        return true
    }
}
