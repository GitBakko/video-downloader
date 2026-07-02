import Foundation
import Observation
import AppKit
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
    var urlField: String = ""
    var updatingYtDlp: Bool = false

    init() {
        let settings = SettingsStore()
        let binaries = BinaryManager()
        let prober = MediaProbe(binaries: binaries)
        let engine = DownloadEngine(binaries: binaries)
        self.settings = settings
        self.binaries = binaries
        self.queue = QueueStore(prober: prober, engine: engine, binaries: binaries, settings: settings)
    }

    // MARK: Bootstrap (spec §5.1)
    func bootstrap() async {
        setupPhase = .installing("Scarico i componenti necessari (yt-dlp, ffmpeg)…")
        do {
            try await binaries.ensureInstalled()
            setupPhase = .ready
        } catch {
            setupPhase = .failed(error.localizedDescription)
        }
    }

    func retrySetup() { Task { await bootstrap() } }

    // MARK: Add URLs (spec §5.2 — supports one-or-more, one per line)
    func addFromField() {
        let urls = urlField
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !urls.isEmpty else { return }
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

    // MARK: Update yt-dlp (spec §5.3)
    func updateYtDlp() {
        guard !updatingYtDlp else { return }
        updatingYtDlp = true
        Task {
            defer { updatingYtDlp = false }
            try? await binaries.updateYtDlp()
        }
    }

    // MARK: Reveal in Finder (spec §5.2)
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
