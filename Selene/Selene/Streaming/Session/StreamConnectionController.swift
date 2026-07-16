import AppKit
import Foundation
import os

private let sessionLogger = Logger(subsystem: "ch.polonium.selene", category: "session")

/// Drives one `GameStreamSession` (the `LiStartConnection` bridge) and
/// surfaces its stage progress for the UI. Also owns the `VideoDecodeRenderer`
/// (its `AVSampleBufferDisplayLayer` gets hosted in SwiftUI once connected)
/// and the `AudioDecodeRenderer`. No input is wired up yet.
@MainActor
@Observable
final class StreamConnectionController: NSObject, GameStreamSessionDelegate {
    private(set) var isConnected = false

    let videoRenderer = VideoDecodeRenderer()
    private let audioRenderer = AudioDecodeRenderer()
    private let inputForwarder = InputForwarder()
    private let gamepadForwarder = GamepadForwarder.shared
    private var session: GameStreamSession?

    /// Fired when the user presses the background hotkey (Ctrl+Option+Shift+Q)
    /// during a stream - see `InputForwarder`.
    var onBackgroundRequested: (() -> Void)? {
        get { inputForwarder.onBackgroundRequested }
        set { inputForwarder.onBackgroundRequested = newValue }
    }

    /// The stream's own NSWindow - gates input capture to only fire while
    /// this specific window is key (see `InputForwarder`). Set this as soon
    /// as the window is known, so it's already recorded by the time
    /// `inputForwarder.start()` runs after the connection comes up.
    var streamWindow: NSWindow? {
        get { inputForwarder.targetWindow }
        set { inputForwarder.targetWindow = newValue }
    }

    func start(address: String, serverAppVersion: String, rtspSessionUrl: String?, config: StreamSessionConfig) {
        let session = GameStreamSession(delegate: self, videoRenderer: videoRenderer, audioRenderer: audioRenderer)
        self.session = session
        session.start(
            withAddress: address,
            serverAppVersion: serverAppVersion,
            rtspSessionUrl: rtspSessionUrl,
            width: config.width,
            height: config.height,
            fps: config.fps,
            bitrateKbps: config.bitrateKbps,
            remoteInputAesKey: config.remoteInputAesKey,
            remoteInputAesIv: config.remoteInputAesIv,
            audioChannelCount: config.audioChannelCount,
            audioChannelMask: config.audioChannelMask,
            packetSize: SettingsStore.packetSize
        )
    }

    func stop() {
        session?.stop()
        videoRenderer.reset()
        audioRenderer.reset()
        inputForwarder.stop()
        gamepadForwarder.stop()
    }

    // These are invoked by GameStreamSession.mm via dispatch_async(dispatch_get_main_queue()),
    // so we really are already on the main thread - `assumeIsolated` just proves
    // that to Swift's strict concurrency checker instead of hopping again with
    // an extra Task (which would also reorder these relative to each other).
    nonisolated func gameStreamSessionStageStarting(_ stage: String) {
        sessionLogger.notice("stage starting: \(stage, privacy: .public)")
    }

    nonisolated func gameStreamSessionStageComplete(_ stage: String) {
        sessionLogger.notice("stage complete: \(stage, privacy: .public)")
    }

    nonisolated func gameStreamSessionStageFailed(_ stage: String, errorCode: Int32) {
        sessionLogger.error("stage FAILED: \(stage, privacy: .public) code=\(errorCode, privacy: .public)")
    }

    nonisolated func gameStreamSessionConnectionStarted() {
        sessionLogger.notice("connection started")
        MainActor.assumeIsolated {
            isConnected = true
            inputForwarder.start()
            gamepadForwarder.start()
        }
    }

    nonisolated func gameStreamSessionConnectionTerminatedWithErrorCode(_ errorCode: Int32) {
        sessionLogger.notice("connection terminated code=\(errorCode, privacy: .public)")
        MainActor.assumeIsolated {
            isConnected = false
            inputForwarder.stop()
            gamepadForwarder.stop()
        }
    }

    nonisolated func gameStreamSessionLogMessage(_ message: String) {
        sessionLogger.notice("\(message, privacy: .public)")
    }
}
