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
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
            CommandGroup(after: .appInfo) {
                Button("Aggiorna yt-dlp") { app.updateYtDlp() }
                    .disabled(app.updatingYtDlp)
            }
        }

        Window("Aiuto — Video Downloader", id: "help") {
            HelpView()
                .environment(app)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(app)
                .frame(width: 480)
        }
    }
}

/// Menu command that opens the Help window (replaces the empty default Help item).
private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Aiuto Video Downloader") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}
