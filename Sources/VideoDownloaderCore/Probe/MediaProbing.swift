import Foundation

/// Abstraction over "probe this URL and return its downloadable items" (spec §6).
/// Implemented for real by `MediaProbe` (Phase 7) and faked in tests.
public protocol MediaProbing {
    func probe(url: String) async throws -> [DownloadItem]
}
