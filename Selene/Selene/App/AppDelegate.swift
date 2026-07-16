import Cocoa
import Sparkle

/// Owns the Sparkle updater. SwiftUI's `App` protocol has no lifecycle hook
/// early enough to start Sparkle itself, so this is wired in via
/// `@NSApplicationDelegateAdaptor` in `SeleneApp`, matching Sparkle's
/// documented SwiftUI integration.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController: SPUStandardUpdaterController

    override init() {
        // startingUpdater: true begins Sparkle's automatic background check
        // schedule (SUEnableAutomaticChecks/SUScheduledCheckInterval in
        // Info.plist) as soon as the app launches.
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    // Warms GamepadForwarder.shared as early as possible, so GCController has
    // time to enumerate already-connected pads before the user ever hits
    // "launch app" (GameStreamClient.launchApp reads its mask synchronously).
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = GamepadForwarder.shared
    }
}
