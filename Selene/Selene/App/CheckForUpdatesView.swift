import SwiftUI
import Sparkle

/// `SPUUpdater.canCheckForUpdates` is KVO-observable (it's false while a
/// check/update is already in progress) - bridging it to `@Published` is
/// Sparkle's own documented way to drive a SwiftUI menu command's enabled
/// state correctly.
@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

/// The "Check for Updates…" menu command's content - lives in the app's
/// `.commands` block since Sparkle doesn't provide its own SwiftUI menu item.
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
