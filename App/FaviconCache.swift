import SwiftUI
import AppKit

/// Persistent, deduplicated favicon store keyed by host.
///
/// Lookup order for a host:
///   1. in-memory cache (this session)
///   2. on-disk cache: `~/Library/Application Support/VideoDownloader/favicons/<host>.png`
///   3. download once from a favicon service, save to disk, cache in memory
///
/// Concurrent requests for the same host share a single in-flight download, so a
/// 30-item YouTube playlist fetches the youtube.com favicon exactly once.
actor FaviconCache {
    static let shared = FaviconCache()

    private let dir: URL
    private let session: URLSession
    private var memory: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("VideoDownloader/favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func icon(forHost rawHost: String) async -> NSImage? {
        let host = rawHost.lowercased()
        guard !host.isEmpty else { return nil }
        if let cached = memory[host] { return cached }
        if let running = inFlight[host] { return await running.value }

        // Create + register the in-flight task synchronously (no suspension between
        // the inFlight check above and this assignment) so concurrent callers dedupe.
        let task = Task<NSImage?, Never> { [self] in await load(host: host) }
        inFlight[host] = task
        let image = await task.value
        inFlight[host] = nil
        if let image { memory[host] = image }
        return image
    }

    private func load(host: String) async -> NSImage? {
        let file = dir.appendingPathComponent(sanitize(host) + ".png")
        if let data = await Self.readFile(file), let image = NSImage(data: data) {
            return image
        }
        // Favicon service: reliable, returns a normalized PNG, no per-site scraping.
        // Only the bare host is sent. Swappable if you prefer another provider.
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data)
        else { return nil }
        Self.writeFile(data, to: file)   // persist the raw PNG for reuse across launches
        return image
    }

    /// Read the cached PNG off the cooperative pool: `Data(contentsOf:)` is a
    /// blocking syscall, and running it directly on the actor would stall the
    /// cooperative thread while the disk responds (P14). Only `Data` (Sendable)
    /// crosses the boundary; the `NSImage` is decoded back on the actor.
    private static func readFile(_ url: URL) async -> Data? {
        await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
    }

    /// Persist the PNG without blocking the actor (fire-and-forget; P14).
    private static func writeFile(_ data: Data, to url: URL) {
        Task.detached(priority: .utility) { try? data.write(to: url) }
    }

    private func sanitize(_ host: String) -> String {
        host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
            .reduce(into: "") { $0.append($1) }
    }
}

/// Small favicon for a host — falls back to a globe while loading or on failure.
struct FaviconView: View {
    let host: String
    var size: CGFloat = 14
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
                    .transition(.opacity)
            } else {
                Image(systemName: "globe").resizable().foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        // Decorative: the adjacent site name / host already conveys the source, so
        // the icon (and its globe fallback) is hidden from VoiceOver (M6).
        .accessibilityHidden(true)
        // Gentle cross-fade when the real favicon replaces the globe (P4).
        .animation(.easeInOut(duration: 0.2), value: image != nil)
        .task(id: host) { image = await FaviconCache.shared.icon(forHost: host) }
    }
}
