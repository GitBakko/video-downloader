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
                // Also persist the list and, if it holds finished rows, ask
                // whether to prune them before exiting (see AppDelegate).
                .onAppear {
                    appDelegate.onTerminate = { app.queue.cancelAll() }
                    // Blocking: the app exits right after, so the write must finish
                    // synchronously or it's lost.
                    appDelegate.onPersist = { app.queue.saveNow(blocking: true) }
                    appDelegate.hasFinishedItems = { app.queue.hasFinishedItems }
                    appDelegate.removeFinishedItems = { app.queue.removeFinished() }
                }
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
                WhatsNewMenuButton()
                Button("Aggiorna yt-dlp") { app.updateYtDlp() }
                    .disabled(app.updatingYtDlp)
            }
            CommandGroup(after: .sidebar) {
                HistoryMenuButton()
            }
        }

        Window("Cronologia", id: "history") {
            HistoryView()
                .environment(app)
        }
        .windowResizability(.contentSize)

        Window("Aiuto — Video Downloader", id: "help") {
            HelpView()
                .environment(app)
        }
        .windowResizability(.contentSize)

        Window("Novità — Video Downloader", id: "whatsnew") {
            ChangelogView()
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

/// Menu command (app menu) that opens the in-app release history window.
private struct WhatsNewMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Novità…") { openWindow(id: "whatsnew") }
    }
}

/// Menu command (View menu) that opens the download history window.
private struct HistoryMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Cronologia download") { openWindow(id: "history") }
            .keyboardShortcut("y", modifiers: .command)
    }
}

/// App delegate that, on quit: saves the queue, optionally prompts to drop the
/// finished rows, then tears down running downloads (S16). These callbacks are
/// set from the window's `onAppear`. `applicationShouldTerminate` runs
/// synchronously on the main thread while the app is exiting, so we can't defer
/// to a `Task` (it may never run) — we assume the main-actor isolation we're
/// already on and call straight through.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `QueueStore.cancelAll()` — kill every in-flight yt-dlp child.
    var onTerminate: (@MainActor () -> Void)?
    /// `QueueStore.saveNow()` — flush the list to disk.
    var onPersist: (@MainActor () -> Void)?
    /// `QueueStore.hasFinishedItems` — any completed/failed/cancelled row?
    var hasFinishedItems: (@MainActor () -> Bool)?
    /// `QueueStore.removeFinished()` — drop the finished rows from the list.
    var removeFinishedItems: (@MainActor () -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            // Save FIRST, while in-flight rows are still `.downloading`: the
            // snapshot restores them as resumable `.ready` next launch. (cancelAll
            // below flips them to `.cancelled`, which we don't want persisted.)
            onPersist?()

            // If nothing is finished, quit straight away.
            guard hasFinishedItems?() == true else {
                onTerminate?()
                return .terminateNow
            }

            let alert = NSAlert()
            alert.messageText = "Rimuovere i download terminati dalla lista?"
            alert.informativeText = "Alcuni download sono completati o annullati. Vuoi rimuoverli dalla lista prima di uscire? I download non terminati restano e potrai riprenderli al prossimo avvio."
            alert.addButton(withTitle: "Rimuovi ed esci")   // .alertFirstButtonReturn
            alert.addButton(withTitle: "Mantieni ed esci")  // .alertSecondButtonReturn
            alert.addButton(withTitle: "Annulla")           // .alertThirdButtonReturn
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                removeFinishedItems?()
                onPersist?()          // re-save the pruned list
            case .alertThirdButtonReturn:
                return .terminateCancel  // stay open
            default:
                break                 // keep the list as-is
            }
            onTerminate?()
            return .terminateNow
        }
    }
}
