import SwiftUI
import AppKit
import VideoDownloaderCore

@main
struct VideoDownloaderApp: App {
    @State private var app = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                // S16: terminate every in-flight yt-dlp child on quit so no
                // orphaned process reparents to launchd and keeps writing files.
                .onAppear { appDelegate.onTerminate = { app.queue.cancelAll() } }
        }
        // S4: the window frame is driven per setup phase inside `RootView`
        // (compact during first-launch install, full-size once ready). With
        // `.contentSize` resizability the window tracks that content size.
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

/// App delegate whose sole job is to tear down running downloads on quit (S16).
/// `applicationWillTerminate` runs synchronously on the main thread while the app
/// is exiting, so we can't defer to a `Task` (it may never run) — we assume the
/// main-actor isolation we're already on and call straight through.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once from the window's `onAppear`; calls `QueueStore.cancelAll()`.
    var onTerminate: (@MainActor () -> Void)?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { onTerminate?() }
    }
}
