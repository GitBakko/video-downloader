import SwiftUI
import AppKit
import Combine
import VideoDownloaderCore

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.setupPhase == .ready {
                // Full-size, resizable main window.
                MainWindowView()
                    .frame(minWidth: 760, minHeight: 520)
            } else {
                // S4/P6: keep the window compact while the first-launch install
                // runs, so the setup card fills it instead of floating in a huge
                // empty 760×520 frame. Expands once `setupPhase == .ready`. The
                // failed phase gets a little more room for its error + Riprova.
                SetupView()
                    .frame(width: setupSize.width, height: setupSize.height)
            }
        }
        .task {
            if app.setupPhase != .ready { await app.bootstrap() }
        }
        // macOS has no pasteboard-change event, so poll the clipboard on a timer:
        // a copied link is caught whether or not the app has focus (the old
        // "only on focus regain" check missed most copies). Plus an instant check
        // when the app becomes active.
        .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in
            if app.setupPhase == .ready { app.pollClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if app.setupPhase == .ready { app.pollClipboard() }
        }
    }

    /// Compact by default; a touch taller when showing an install error so the
    /// message and "Riprova" button don't clip.
    private var setupSize: CGSize {
        if case .failed = app.setupPhase { return CGSize(width: 460, height: 340) }
        return CGSize(width: 420, height: 260)
    }
}
