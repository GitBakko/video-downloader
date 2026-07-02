import SwiftUI
import VideoDownloaderCore

@main
struct VideoDownloaderApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Aggiorna yt-dlp") { app.updateYtDlp() }
                    .disabled(app.updatingYtDlp)
            }
        }
    }
}
