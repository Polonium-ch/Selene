import SwiftUI

/// The app's native `Settings` scene (⌘, / app menu) - three category tabs
/// matching the surface area of the legacy Qt client's `StreamingPreferences`
/// (`app/settings/streamingpreferences.h`). Not every control here changes
/// stream behavior yet; see `SettingsStore`'s per-property doc comments for
/// which ones are actually wired up versus persisted-only for now. The
/// persisted-only ones are shown disabled with a "Not Yet" badge (below)
/// rather than silently doing nothing when touched.
struct SettingsView: View {
    var body: some View {
        TabView {
            VideoSettingsView()
                .tabItem { Label("Video", systemImage: "tv") }
            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
            NetworkSettingsView()
                .tabItem { Label("Network", systemImage: "network") }
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Marks a control that's persisted in `SettingsStore` but doesn't affect
/// stream behavior yet - paired with `.disabled(true)` on the control itself
/// so it reads as "not built yet" rather than "broken".
private struct NotYetBadge: View {
    var body: some View {
        Text("Not Yet")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

/// Row label for a not-yet-wired control: title + `NotYetBadge`. Pair with
/// `.disabled(true)` on the `Toggle`/`Picker` itself.
private struct NotYetLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            NotYetBadge()
        }
    }
}

private struct VideoSettingsView: View {
    @State private var resolution = SettingsStore.resolution
    @State private var fps = SettingsStore.fps
    @State private var bitrateKbps = SettingsStore.bitrateKbps
    @State private var unlockBitrate = SettingsStore.unlockBitrate
    @State private var autoAdjustBitrate = SettingsStore.autoAdjustBitrate
    @State private var enableVsync = SettingsStore.enableVsync
    @State private var videoCodec = SettingsStore.videoCodec
    @State private var enableHdr = SettingsStore.enableHdr
    @State private var enableYUV444 = SettingsStore.enableYUV444
    @State private var videoDecoder = SettingsStore.videoDecoder
    @State private var framePacing = SettingsStore.framePacing
    @State private var showPerformanceOverlay = SettingsStore.showPerformanceOverlay

    /// 5-150 Mbps normally, 5-500 once "Unlock bitrate" is on - the toggle's
    /// only real effect today (see `SettingsStore.unlockBitrate`).
    private var bitrateRangeMbps: ClosedRange<Double> {
        unlockBitrate ? 5...500 : 5...150
    }

    var body: some View {
        Form {
            Section {
                Picker("Resolution", selection: $resolution) {
                    ForEach(StreamResolution.allCases) { Text($0.label).tag($0) }
                }
                Picker("Frame Rate", selection: $fps) {
                    ForEach([Int32(30), 60, 90, 120], id: \.self) { Text("\($0) fps").tag($0) }
                }
                VStack(alignment: .leading) {
                    Slider(
                        value: Binding(
                            get: { Double(bitrateKbps) / 1000 },
                            set: { bitrateKbps = Int32($0 * 1000) }
                        ),
                        in: bitrateRangeMbps,
                        step: 1
                    ) {
                        Text("Bitrate")
                    }
                    Text("\(bitrateKbps / 1000) Mbps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Unlock Bitrate", isOn: $unlockBitrate)

                Toggle(isOn: $autoAdjustBitrate) { NotYetLabel(title: "Auto-Adjust Bitrate") }
                    .disabled(true)
            }

            Section {
                Picker(selection: $videoCodec) {
                    ForEach(VideoCodecPreference.allCases) { Text($0.label).tag($0) }
                } label: { NotYetLabel(title: "Codec") }
                    .disabled(true)

                Picker(selection: $videoDecoder) {
                    ForEach(VideoDecoderPreference.allCases) { Text($0.label).tag($0) }
                } label: { NotYetLabel(title: "Decoder") }
                    .disabled(true)

                Toggle(isOn: $enableHdr) { NotYetLabel(title: "HDR") }
                    .disabled(true)
                Toggle(isOn: $enableYUV444) { NotYetLabel(title: "YUV 4:4:4") }
                    .disabled(true)
                Toggle(isOn: $enableVsync) { NotYetLabel(title: "V-Sync") }
                    .disabled(true)
                Toggle(isOn: $framePacing) { NotYetLabel(title: "Frame Pacing") }
                    .disabled(true)
                Toggle(isOn: $showPerformanceOverlay) { NotYetLabel(title: "Show Performance Overlay") }
                    .disabled(true)
            }
        }
        .formStyle(.grouped)
        .onChange(of: resolution) { _, newValue in SettingsStore.resolution = newValue }
        .onChange(of: fps) { _, newValue in SettingsStore.fps = newValue }
        .onChange(of: bitrateKbps) { _, newValue in SettingsStore.bitrateKbps = newValue }
        .onChange(of: unlockBitrate) { _, newValue in SettingsStore.unlockBitrate = newValue }
        .onChange(of: autoAdjustBitrate) { _, newValue in SettingsStore.autoAdjustBitrate = newValue }
        .onChange(of: enableVsync) { _, newValue in SettingsStore.enableVsync = newValue }
        .onChange(of: videoCodec) { _, newValue in SettingsStore.videoCodec = newValue }
        .onChange(of: enableHdr) { _, newValue in SettingsStore.enableHdr = newValue }
        .onChange(of: enableYUV444) { _, newValue in SettingsStore.enableYUV444 = newValue }
        .onChange(of: videoDecoder) { _, newValue in SettingsStore.videoDecoder = newValue }
        .onChange(of: framePacing) { _, newValue in SettingsStore.framePacing = newValue }
        .onChange(of: showPerformanceOverlay) { _, newValue in SettingsStore.showPerformanceOverlay = newValue }
    }
}

private struct AudioSettingsView: View {
    @State private var audioConfig = SettingsStore.audioConfig
    @State private var playAudioOnHost = SettingsStore.playAudioOnHost
    @State private var muteOnFocusLoss = SettingsStore.muteOnFocusLoss

    var body: some View {
        Form {
            Section {
                Picker("Audio Configuration", selection: $audioConfig) {
                    ForEach(AudioChannelConfig.allCases) { Text($0.label).tag($0) }
                }

                Toggle(isOn: $playAudioOnHost) { NotYetLabel(title: "Play Audio on Host") }
                    .disabled(true)
                Toggle(isOn: $muteOnFocusLoss) { NotYetLabel(title: "Mute on Focus Loss") }
                    .disabled(true)
            }
        }
        .formStyle(.grouped)
        .onChange(of: audioConfig) { _, newValue in SettingsStore.audioConfig = newValue }
        .onChange(of: playAudioOnHost) { _, newValue in SettingsStore.playAudioOnHost = newValue }
        .onChange(of: muteOnFocusLoss) { _, newValue in SettingsStore.muteOnFocusLoss = newValue }
    }
}

private struct NetworkSettingsView: View {
    @State private var httpsPort = SettingsStore.httpsPort
    @State private var packetSize = SettingsStore.packetSize
    @State private var enableMdns = SettingsStore.enableMdns
    @State private var detectNetworkBlocking = SettingsStore.detectNetworkBlocking
    @State private var connectionWarnings = SettingsStore.connectionWarnings

    var body: some View {
        Form {
            Section {
                LabeledContent("HTTPS Port") {
                    TextField("", value: $httpsPort, format: .number.grouping(.never))
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Stepper("Packet Size: \(packetSize) bytes", value: $packetSize, in: 512...1500, step: 8)
            } footer: {
                Text("Only change these if your Sunshine host runs on a non-default HTTPS port or network setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $enableMdns) { NotYetLabel(title: "Enable mDNS Discovery") }
                    .disabled(true)
                Toggle(isOn: $detectNetworkBlocking) { NotYetLabel(title: "Detect Network Blocking") }
                    .disabled(true)
                Toggle(isOn: $connectionWarnings) { NotYetLabel(title: "Connection Warnings") }
                    .disabled(true)
            }
        }
        .formStyle(.grouped)
        .onChange(of: httpsPort) { _, newValue in SettingsStore.httpsPort = newValue }
        .onChange(of: packetSize) { _, newValue in SettingsStore.packetSize = newValue }
        .onChange(of: enableMdns) { _, newValue in SettingsStore.enableMdns = newValue }
        .onChange(of: detectNetworkBlocking) { _, newValue in SettingsStore.detectNetworkBlocking = newValue }
        .onChange(of: connectionWarnings) { _, newValue in SettingsStore.connectionWarnings = newValue }
    }
}

#Preview {
    SettingsView()
}
