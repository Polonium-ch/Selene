import Foundation

/// Video resolution presets offered in Settings - maps 1:1 to
/// `STREAM_CONFIGURATION.width`/`height`.
enum StreamResolution: String, CaseIterable, Identifiable, Codable {
    case r1280x720, r1920x1080, r2560x1440, r3840x2160

    var id: String { rawValue }

    var label: String {
        switch self {
        case .r1280x720: "1280 × 720"
        case .r1920x1080: "1920 × 1080"
        case .r2560x1440: "2560 × 1440"
        case .r3840x2160: "3840 × 2160"
        }
    }

    var dimensions: (width: Int32, height: Int32) {
        switch self {
        case .r1280x720: (1280, 720)
        case .r1920x1080: (1920, 1080)
        case .r2560x1440: (2560, 1440)
        case .r3840x2160: (3840, 2160)
        }
    }
}

/// Audio channel layouts - matches Limelight.h's `AUDIO_CONFIGURATION_STEREO`/
/// `_51_SURROUND`/`_71_SURROUND` (`MAKE_AUDIO_CONFIGURATION(channelCount,
/// channelMask)`) exactly, so these values can drive both the `/launch`
/// `surroundAudioInfo` param and `STREAM_CONFIGURATION.audioConfiguration`.
enum AudioChannelConfig: String, CaseIterable, Identifiable, Codable {
    case stereo, surround51, surround71

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stereo: "Stereo"
        case .surround51: "5.1 Surround"
        case .surround71: "7.1 Surround"
        }
    }

    var channelCount: Int32 {
        switch self {
        case .stereo: 2
        case .surround51: 6
        case .surround71: 8
        }
    }

    var channelMask: Int32 {
        switch self {
        case .stereo: 0x3
        case .surround51: 0x3F
        case .surround71: 0x63F
        }
    }
}

/// Video codec preference. // TODO(settings): liga quando o decoder suportar
/// HEVC/AV1 - hoje `VideoDecodeRenderer`/`GameStreamSession` só decodificam
/// H.264, então isso fica só persistido por enquanto.
enum VideoCodecPreference: String, CaseIterable, Identifiable, Codable {
    case auto, h264, hevc, av1

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Automatic"
        case .h264: "Force H.264"
        case .hevc: "Force HEVC"
        case .av1: "Force AV1"
        }
    }
}

/// Video decoder preference. // TODO(settings): liga quando existir escolha
/// manual de decoder por software - hoje `AVSampleBufferDisplayLayer` sempre
/// decide sozinho (via VideoToolbox), então isso fica só persistido.
enum VideoDecoderPreference: String, CaseIterable, Identifiable, Codable {
    case auto, hardware, software

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Automatic"
        case .hardware: "Force Hardware"
        case .software: "Force Software"
        }
    }
}

/// User-facing streaming preferences, persisted in `UserDefaults` - same
/// plain-enum-over-`UserDefaults.standard` pattern `PairingStore` already
/// uses in this codebase. Read by `SettingsView`'s controls and by whatever
/// builds a `StreamSessionConfig`/launch request at connect time.
///
/// Not every property here changes actual stream behavior yet - see the
/// per-property `// TODO(settings):` comments and the plan this shipped
/// under. They're all persisted now regardless, so no migration is needed
/// once each one gets wired up.
enum SettingsStore {
    private enum Key {
        static let resolution = "settings.video.resolution"
        static let fps = "settings.video.fps"
        static let bitrateKbps = "settings.video.bitrateKbps"
        static let unlockBitrate = "settings.video.unlockBitrate"
        static let autoAdjustBitrate = "settings.video.autoAdjustBitrate"
        static let enableVsync = "settings.video.enableVsync"
        static let videoCodec = "settings.video.codec"
        static let enableHdr = "settings.video.enableHdr"
        static let enableYUV444 = "settings.video.enableYUV444"
        static let videoDecoder = "settings.video.decoder"
        static let framePacing = "settings.video.framePacing"
        static let showPerformanceOverlay = "settings.video.showPerformanceOverlay"

        static let audioConfig = "settings.audio.config"
        static let playAudioOnHost = "settings.audio.playAudioOnHost"
        static let muteOnFocusLoss = "settings.audio.muteOnFocusLoss"

        static let httpsPort = "settings.network.httpsPort"
        static let packetSize = "settings.network.packetSize"
        static let enableMdns = "settings.network.enableMdns"
        static let detectNetworkBlocking = "settings.network.detectNetworkBlocking"
        static let connectionWarnings = "settings.network.connectionWarnings"
    }

    // Computed rather than a stored `static let` - a stored non-Sendable
    // instance in static storage trips Swift 6's concurrency-safety check;
    // `UserDefaults.standard` itself is already a safe shared singleton
    // (matches the plain `UserDefaults.standard.foo()` calls PairingStore
    // uses for the same reason).
    private static var defaults: UserDefaults { .standard }

    private static func enumValue<T: RawRepresentable>(_ key: String, default defaultValue: T) -> T where T.RawValue == String {
        (defaults.string(forKey: key)).flatMap(T.init(rawValue:)) ?? defaultValue
    }

    // MARK: - Video

    /// **Ligado** - flows into `StreamSessionConfig.make(width:height:...)`.
    static var resolution: StreamResolution {
        get { enumValue(Key.resolution, default: .r1920x1080) }
        set { defaults.set(newValue.rawValue, forKey: Key.resolution) }
    }

    /// **Ligado** - flows into `StreamSessionConfig.make(fps:)`.
    static var fps: Int32 {
        get {
            let value = defaults.integer(forKey: Key.fps)
            return value == 0 ? 60 : Int32(value)
        }
        set { defaults.set(Int(newValue), forKey: Key.fps) }
    }

    /// **Ligado** - flows into `StreamSessionConfig.make(bitrateKbps:)`.
    static var bitrateKbps: Int32 {
        get {
            let value = defaults.integer(forKey: Key.bitrateKbps)
            return value == 0 ? 20_000 : Int32(value)
        }
        set { defaults.set(Int(newValue), forKey: Key.bitrateKbps) }
    }

    /// Ligado só na própria UI - estende o teto do slider de bitrate em
    /// `SettingsView`, sem validação contra capacidade real do host.
    static var unlockBitrate: Bool {
        get { defaults.bool(forKey: Key.unlockBitrate) }
        set { defaults.set(newValue, forKey: Key.unlockBitrate) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando existir
    /// lógica de bitrate adaptativo por condição de rede.
    static var autoAdjustBitrate: Bool {
        get { defaults.object(forKey: Key.autoAdjustBitrate) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoAdjustBitrate) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando o
    /// pipeline de vídeo expuser controle de V-Sync.
    static var enableVsync: Bool {
        get { defaults.object(forKey: Key.enableVsync) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enableVsync) }
    }

    /// Persistido, sem efeito ainda - ver `VideoCodecPreference`.
    static var videoCodec: VideoCodecPreference {
        get { enumValue(Key.videoCodec, default: .auto) }
        set { defaults.set(newValue.rawValue, forKey: Key.videoCodec) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando o
    /// decoder suportar HDR.
    static var enableHdr: Bool {
        get { defaults.bool(forKey: Key.enableHdr) }
        set { defaults.set(newValue, forKey: Key.enableHdr) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando o
    /// decoder suportar YUV 4:4:4.
    static var enableYUV444: Bool {
        get { defaults.bool(forKey: Key.enableYUV444) }
        set { defaults.set(newValue, forKey: Key.enableYUV444) }
    }

    /// Persistido, sem efeito ainda - ver `VideoDecoderPreference`.
    static var videoDecoder: VideoDecoderPreference {
        get { enumValue(Key.videoDecoder, default: .auto) }
        set { defaults.set(newValue.rawValue, forKey: Key.videoDecoder) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando existir
    /// controle manual de frame pacing.
    static var framePacing: Bool {
        get { defaults.object(forKey: Key.framePacing) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.framePacing) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando existir
    /// um overlay de performance sobre o vídeo.
    static var showPerformanceOverlay: Bool {
        get { defaults.bool(forKey: Key.showPerformanceOverlay) }
        set { defaults.set(newValue, forKey: Key.showPerformanceOverlay) }
    }

    // MARK: - Audio

    /// **Ligado** - flows into `STREAM_CONFIGURATION.audioConfiguration` and
    /// the `/launch` `surroundAudioInfo` param.
    static var audioConfig: AudioChannelConfig {
        get { enumValue(Key.audioConfig, default: .stereo) }
        set { defaults.set(newValue.rawValue, forKey: Key.audioConfig) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando existir
    /// suporte a `localAudioPlayMode` configurável no launch request.
    static var playAudioOnHost: Bool {
        get { defaults.bool(forKey: Key.playAudioOnHost) }
        set { defaults.set(newValue, forKey: Key.playAudioOnHost) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando
    /// `InputForwarder`/`AudioDecodeRenderer` observar perda de foco da
    /// janela.
    static var muteOnFocusLoss: Bool {
        get { defaults.bool(forKey: Key.muteOnFocusLoss) }
        set { defaults.set(newValue, forKey: Key.muteOnFocusLoss) }
    }

    // MARK: - Network

    /// **Ligado** - substitui o `47984` fixo nos pontos de launch/pairing/
    /// app grid.
    static var httpsPort: UInt16 {
        get {
            let value = defaults.integer(forKey: Key.httpsPort)
            return value == 0 ? 47984 : UInt16(clamping: value)
        }
        set { defaults.set(Int(newValue), forKey: Key.httpsPort) }
    }

    /// **Ligado** - flows into `STREAM_CONFIGURATION.packetSize`.
    static var packetSize: Int32 {
        get {
            let value = defaults.integer(forKey: Key.packetSize)
            return value == 0 ? 1024 : Int32(value)
        }
        set { defaults.set(Int(newValue), forKey: Key.packetSize) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando
    /// `HostDiscoveryService` aceitar ser desligado.
    static var enableMdns: Bool {
        get { defaults.object(forKey: Key.enableMdns) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enableMdns) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando existir
    /// detecção de bloqueio de rede (portas UDP filtradas, etc).
    static var detectNetworkBlocking: Bool {
        get { defaults.object(forKey: Key.detectNetworkBlocking) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.detectNetworkBlocking) }
    }

    /// Persistido, sem efeito ainda. // TODO(settings): liga quando existir
    /// UI de aviso de conexão durante a stream.
    static var connectionWarnings: Bool {
        get { defaults.object(forKey: Key.connectionWarnings) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.connectionWarnings) }
    }
}
