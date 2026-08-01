import Foundation

/// Abstraction over "probe this URL and return its downloadable items" (spec §6).
/// Implemented for real by `MediaProbe` (Phase 7) and faked in tests.
public protocol MediaProbing {
    /// `cookiesBrowser` is the user's `--cookies-from-browser` choice (nil = anonymous).
    /// The probe needs it as much as the download: gated posts fail at extraction.
    func probe(url: String, cookiesBrowser: String?) async throws -> [DownloadItem]
}
