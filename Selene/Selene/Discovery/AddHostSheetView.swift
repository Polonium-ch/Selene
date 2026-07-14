import SwiftUI

/// Lets the user type in a Sunshine host's IP/hostname directly, for cases
/// Bonjour/mDNS discovery can't reach (VPNs, remote networks, etc) -
/// mirrors the legacy Qt client's manual "Add PC" flow
/// (`ComputerManager::addNewHost`), minus the `moonlight://` prefix parsing.
struct AddHostSheetView: View {
    var onAdd: (DiscoveredHost) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add PC by Address")
                .font(.headline)

            Text("Enter the IP address or hostname of a Sunshine PC. Useful when it's not on the same local network (e.g. connecting over a VPN).")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("192.168.1.10", text: $address)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { Task { await addHost() } }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button {
                    Task { await addHost() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func addHost() async {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        let port: UInt16 = 47989
        guard let serverInfo = await SunshineServerInfoFetcher.fetch(ip: trimmed, port: port) else {
            isLoading = false
            errorMessage = "Couldn't reach a Sunshine/GameStream PC at that address."
            return
        }

        let host = DiscoveredHost(
            id: serverInfo.uniqueId ?? trimmed,
            name: serverInfo.hostname ?? trimmed,
            resolvedHost: trimmed,
            port: port,
            txtRecord: [:],
            lastUpdated: Date(),
            serverUniqueId: serverInfo.uniqueId,
            appVersion: serverInfo.appVersion
        )

        isLoading = false
        onAdd(host)
        dismiss()
    }
}
