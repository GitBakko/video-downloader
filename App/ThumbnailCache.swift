import SwiftUI
import AppKit

/// In-memory thumbnail store keyed by URL, mirroring `FaviconCache` (M8).
///
/// `AsyncImage` keeps no cache, so a thumbnail is re-fetched — and visibly
/// flashes — every time its row scrolls back into view. This actor keeps decoded
/// images for the session and shares a single in-flight download per URL, so a
/// row that appears, scrolls away, and returns loads its thumbnail exactly once.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let session: URLSession
    private var memory: [URL: NSImage] = [:]
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = memory[url] { return cached }
        if let running = inFlight[url] { return await running.value }

        // Create + register the in-flight task synchronously (no suspension
        // between the check above and this assignment) so concurrent callers
        // dedupe onto one download.
        let task = Task<NSImage?, Never> { [self] in await load(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory[url] = image }
        return image
    }

    private func load(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return NSImage(data: data)
    }
}
