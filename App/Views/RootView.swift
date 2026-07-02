import SwiftUI
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
    }
}
