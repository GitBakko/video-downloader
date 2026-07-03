import Foundation

/// The stream of events a `Downloading` implementation emits for one item (spec §6).
/// `DownloadEvent` has associated values and is intentionally **not** `Equatable`;
/// consumers destructure it with `if case` / `guard case`.
public enum DownloadEvent {
    case progress(percent: Double?, speed: String?, eta: String?, stage: String?)
    case processing
    case finished(outputPath: URL?)
}

/// Abstraction over "run a download for this item and stream its events".
/// Implemented for real by `DownloadEngine` (Phase 6) and faked in tests.
public protocol Downloading {
    func events(for item: DownloadItem, arguments: [String]) -> AsyncThrowingStream<DownloadEvent, Error>
    func cancel(_ id: UUID)
    /// Terminate every in-flight process this engine started. Called on app quit
    /// so no orphaned yt-dlp process is left behind (spec §5 / S16).
    func terminateAll()
}
