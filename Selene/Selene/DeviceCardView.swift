import SwiftUI

/// A device tile for the grid layout, inspired by Windows App's device
/// cards: a large gradient tile with the device name and resolved IP
/// overlaid at the bottom, a hover-revealed favorite toggle, and a
/// Mac-style click-to-select ring.
struct DeviceCardView: View {
    let host: DiscoveredHost
    @Binding var isFavorite: Bool
    var isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(Self.tint(for: host).gradient)

            GeometryReader { proxy in
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: proxy.size.width * 0.8)
                    .offset(x: proxy.size.width * 0.4, y: -proxy.size.height * 0.35)
                    .blur(radius: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let resolvedHost = host.resolvedHost {
                    Text(resolvedHost)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .padding(14)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovering || isFavorite {
                Button {
                    isFavorite.toggle()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isFavorite ? .yellow : .white)
                        .padding(6)
                        .background(.black.opacity(0.25), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    /// A curated, stable-per-host color (not a rainbow hash) - the same
    /// restrained palette approach macOS itself uses for Reminders lists
    /// and Calendar calendars.
    ///
    /// Uses a manual FNV-1a hash rather than `String.hashValue`, which is
    /// deliberately re-seeded per process launch (hash-flooding
    /// resistance) - a host would otherwise get a different color every
    /// time the app restarts.
    static func tint(for host: DiscoveredHost) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan]
        return palette[stableHash(host.id) % palette.count]
    }

    private static func stableHash(_ string: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Int(hash % UInt64(Int.max))
    }
}
