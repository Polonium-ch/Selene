import Foundation
import os

private let sessionLogger = Logger(subsystem: "ch.useselene.selene", category: "session")

/// Drives one `GameStreamSession` (the `LiStartConnection` bridge) and
/// surfaces its stage progress for the UI. Also owns the `VideoDecodeRenderer`
/// so its `AVSampleBufferDisplayLayer` can be hosted in SwiftUI once
/// connected. No audio/input is wired up yet.
@MainActor
@Observable
final class StreamConnectionController: NSObject, GameStreamSessionDelegate {
    private(set) var log: [String] = []
    private(set) var isConnected = false

    let videoRenderer = VideoDecodeRenderer()
    private var session: GameStreamSession?

    func start(address: String, serverAppVersion: String, rtspSessionUrl: String?, config: StreamSessionConfig) {
        let session = GameStreamSession(delegate: self, videoRenderer: videoRenderer)
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
            remoteInputAesIv: config.remoteInputAesIv
        )
    }

    func stop() {
        session?.stop()
        videoRenderer.reset()
    }

    // These are invoked by GameStreamSession.mm via dispatch_async(dispatch_get_main_queue()),
    // so we really are already on the main thread - `assumeIsolated` just proves
    // that to Swift's strict concurrency checker instead of hopping again with
    // an extra Task (which would also reorder these relative to each other).
    nonisolated func gameStreamSessionStageStarting(_ stage: String) {
        sessionLogger.notice("stage starting: \(stage, privacy: .public)")
        MainActor.assumeIsolated {
            log.append("Starting: \(stage)")
        }
    }

    nonisolated func gameStreamSessionStageComplete(_ stage: String) {
        sessionLogger.notice("stage complete: \(stage, privacy: .public)")
        MainActor.assumeIsolated {
            log.append("Complete: \(stage)")
        }
    }

    nonisolated func gameStreamSessionStageFailed(_ stage: String, errorCode: Int32) {
        sessionLogger.error("stage FAILED: \(stage, privacy: .public) code=\(errorCode, privacy: .public)")
        MainActor.assumeIsolated {
            log.append("FAILED: \(stage) (code \(errorCode))")
        }
    }

    nonisolated func gameStreamSessionConnectionStarted() {
        sessionLogger.notice("connection started")
        MainActor.assumeIsolated {
            isConnected = true
            log.append("Connection started!")
        }
    }

    nonisolated func gameStreamSessionConnectionTerminatedWithErrorCode(_ errorCode: Int32) {
        sessionLogger.notice("connection terminated code=\(errorCode, privacy: .public)")
        MainActor.assumeIsolated {
            isConnected = false
            log.append("Terminated (code \(errorCode))")
        }
    }

    nonisolated func gameStreamSessionLogMessage(_ message: String) {
        sessionLogger.notice("\(message, privacy: .public)")
    }
}
