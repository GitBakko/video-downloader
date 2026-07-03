import Foundation
import Observation
import AppKit
import UserNotifications
import VideoDownloaderCore

@MainActor
@Observable
final class AppModel {

    enum SetupPhase: Equatable {
        case installing(String)
        case ready
        case failed(String)
    }

    // Real dependencies (spec §3)
    let settings: SettingsStore
    let binaries: BinaryManager
    let queue: QueueStore

    // UI state
    var setupPhase: SetupPhase = .installing("Verifica dei componenti…")
    /// Overall first-launch download progress (`0...1`); `nil` means indeterminate.
    var setupProgress: Double?
    var urlField: String = ""
    var updatingYtDlp: Bool = false
    /// Observable mirror of `binaries.ytDlpVersion` (which isn't observable itself),
    /// so Settings updates when the warm-up / update finishes (M7).
    var ytDlpVersion: String?
    /// Last yt-dlp update failure, shown under the Settings row; `nil` when the
    /// last update succeeded or none has run (M2).
    var updateError: String?
    /// Set when the destination folder can't be written to, surfaced above the
    /// queue so a start doesn't fail later with a raw yt-dlp errno (P16).
    var destinationError: String?
    /// Guards against a rapid double-tap of "Riprova" spawning two bootstraps (S15).
    private var bootstrapping = false
    private var lastClipboardSuggestion: String?
    private let notificationPresenter = NotificationForegroundPresenter()

    init() {
        let settings = SettingsStore()
        let binaries = BinaryManager()
        let prober = MediaProbe(binaries: binaries)
        let engine = DownloadEngine(binaries: binaries)
        self.settings = settings
        self.binaries = binaries
        self.queue = QueueStore(prober: prober, engine: engine, binaries: binaries, settings: settings)
        // Announce completions from the queue itself, so items that finish while
        // the window is closed are still notified (spec §5.2 / §9).
        self.queue.onItemFinished = { [weak self] item in
            self?.postFinishedNotification(for: item)
        }
    }

    // MARK: Bootstrap (spec §5.1)
    func bootstrap() async {
        bootstrapping = true                 // set before the first await (S15)
        defer { bootstrapping = false }
        setupPhase = .installing("Scarico i componenti necessari (yt-dlp, ffmpeg)…")
        setupProgress = nil
        do {
            try await binaries.ensureInstalled(onProgress: { [weak self] frac in
                // Each callback hops onto the main actor via its own Task, so
                // reports can drain out of order; funnel through a single
                // monotonic setter so the bar never jumps backwards (P12).
                Task { @MainActor in self?.reportSetupProgress(frac) }
            })
            setupProgress = nil
            setupPhase = .ready
            suggestClipboardURL()
            // Warm up yt-dlp in the background so the main window appears instantly.
            // (The onedir's one-time ~24s Gatekeeper scan used to freeze setup at 100%.)
            Task {
                await binaries.prepareYtDlp()
                ytDlpVersion = binaries.ytDlpVersion   // publish for Settings (M7)
            }
        } catch {
            setupProgress = nil
            setupPhase = .failed(error.localizedDescription)
        }
        // Requested OFF the critical path, fire-and-forget: in some run contexts
        // (unsigned/dev builds launched from Xcode) UNUserNotificationCenter can
        // hang, and it must never block the app from becoming usable.
        Task { await requestNotificationAuthorization() }
    }

    /// Monotonic, main-actor-isolated progress setter: only moves the bar forward
    /// and only while still installing, so out-of-order drains can't rewind it (P12).
    private func reportSetupProgress(_ frac: Double) {
        guard case .installing = setupPhase else { return }
        if frac >= (setupProgress ?? 0) { setupProgress = frac }
    }

    func retrySetup() {
        guard case .failed = setupPhase else { return }
        guard !bootstrapping else { return }   // ignore a double-tap while one is running (S15)
        Task { await bootstrap() }
    }

    // MARK: Add URLs (spec §5.2 — supports one-or-more, one per line)
    func addFromField() {
        let urls = urlField
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !urls.isEmpty else { return }
        // Pre-flight the destination so a broken folder shows a clear message here
        // instead of surfacing later as a raw yt-dlp errno mid-download (P16).
        destinationError = validateDestination()
        lastClipboardSuggestion = urls.last
        urlField = ""
        // `QueueStore.add(url:)` is `async` (it awaits the yt-dlp probe), so it
        // must be driven from a `Task`; a bare call here is a compile error.
        // Sequential `await` means each item is appended before the next dedup
        // check runs, so duplicates within `urls` are skipped correctly.
        Task {
            for u in urls where !queue.items.contains(where: { $0.url == u }) {
                await queue.add(url: u)
            }
        }
    }

    /// Returns a user-facing message if the download folder can't be written to,
    /// otherwise `nil`. Creates the folder if it's simply missing (P16).
    private func validateDestination() -> String? {
        let dest = settings.destination
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: dest.path, isDirectory: &isDir) {
            do {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            } catch {
                return "Impossibile creare la cartella di destinazione (\(dest.path(percentEncoded: false))). Scegline un'altra dalle Impostazioni."
            }
        } else if !isDir.boolValue {
            return "La destinazione non è una cartella (\(dest.path(percentEncoded: false))). Scegline un'altra dalle Impostazioni."
        }
        if !fm.isWritableFile(atPath: dest.path) {
            return "La cartella di destinazione non è scrivibile (\(dest.path(percentEncoded: false))). Scegline un'altra dalle Impostazioni."
        }
        return nil
    }

    // MARK: Update yt-dlp (spec §5.3)
    func updateYtDlp() {
        guard !updatingYtDlp else { return }
        updatingYtDlp = true
        updateError = nil
        Task {
            defer { updatingYtDlp = false }
            do {
                try await binaries.updateYtDlp()
                updateError = nil
                ytDlpVersion = binaries.ytDlpVersion   // reflect the new version (M7)
            } catch {
                // Surface the failure instead of swallowing it with `try?` (M2).
                updateError = error.localizedDescription
            }
        }
    }

    // MARK: Reveal in Finder (spec §5.2)
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Notifications + sound (spec §5.2 / §9)
    func requestNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationPresenter
        // Register the "Mostra nel Finder" action shown on completion banners.
        let reveal = UNNotificationAction(
            identifier: NotificationForegroundPresenter.revealActionID,
            title: "Mostra nel Finder",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: NotificationForegroundPresenter.completedCategoryID,
            actions: [reveal],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func postFinishedNotification(for item: DownloadItem) {
        let content = UNMutableNotificationContent()
        content.title = "Download completato"
        content.body = item.title ?? item.url
        content.sound = .default
        content.categoryIdentifier = NotificationForegroundPresenter.completedCategoryID
        if let path = item.outputPath?.path {
            content.userInfo = [NotificationForegroundPresenter.outputPathKey: path]
        }
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        // A fresh copy per play, so two near-simultaneous completions don't collide
        // on the shared named sound (which logs "NSSound … Already playing").
        (NSSound(named: NSSound.Name("Glass"))?.copy() as? NSSound)?.play()
    }

    // MARK: Clipboard proposal (spec §3.6 / §5.2)
    func suggestClipboardURL() {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppModel.looksLikeURL(candidate) else { return }
        guard candidate != lastClipboardSuggestion else { return }          // don't re-propose the same
        // Fill an empty field, or REPLACE a previous auto-suggestion the user
        // hasn't touched — but never clobber text the user actually typed. (Bug:
        // only the first copied link was captured because the field still held the
        // previous suggestion, so this guard rejected every later link.)
        guard urlField.isEmpty || urlField == lastClipboardSuggestion else { return }
        guard !queue.items.contains(where: { $0.url == candidate }) else { return } // skip already added
        urlField = candidate
        lastClipboardSuggestion = candidate
    }

    static func looksLikeURL(_ s: String) -> Bool {
        guard !s.isEmpty, !s.contains(where: { $0 == " " || $0.isNewline }) else { return false }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && (url.host?.isEmpty == false)
    }
}

/// Lets notifications appear while the app is frontmost and reveals the finished
/// file in the Finder when the notification (or its action) is activated.
final class NotificationForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let completedCategoryID = "DOWNLOAD_COMPLETED"
    static let revealActionID = "REVEAL_IN_FINDER"
    static let outputPathKey = "outputPath"

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let path: String? = (action == Self.revealActionID || action == UNNotificationDefaultActionIdentifier)
            ? response.notification.request.content.userInfo[Self.outputPathKey] as? String
            : nil
        // `NSWorkspace` is a main-thread API but this delegate can be called off
        // the main thread, so hop onto the main actor before touching it — and
        // call the completion handler from there too (S10).
        Task { @MainActor in
            if let path {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            completionHandler()
        }
    }
}
