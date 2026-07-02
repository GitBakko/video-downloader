import SwiftUI
import AppKit
import VideoDownloaderCore

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.setupPhase == .ready {
                MainWindowView()
            } else {
                SetupView()
            }
        }
        .task {
            if app.setupPhase != .ready { await app.bootstrap() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if app.setupPhase == .ready { app.suggestClipboardURL() }
        }
    }
}
