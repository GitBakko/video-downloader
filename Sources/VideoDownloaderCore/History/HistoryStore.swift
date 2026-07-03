import Foundation
import Observation

/// Persistent store of completed downloads (the history window's model).
///
/// Mirrors `SettingsStore`/`QueueStore`: `@MainActor @Observable`, with the
/// backing file injectable so tests use a throwaway temp path. Entries are kept
/// newest-first. Writes happen off the main thread so recording a completion
/// never blocks the UI; the initial read is synchronous (small file, once).
@MainActor
@Observable
public final class HistoryStore {

    public private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private let fileURL: URL
    /// Serial queue for disk writes so rapid `record`s persist in order — two
    /// unordered `Task.detached` writes could otherwise race and leave the file
    /// holding an older snapshot (a newer write finishing before an older one).
    @ObservationIgnored private let writeQueue = DispatchQueue(label: "HistoryStore.write", qos: .utility)

    public init(fileURL: URL = HistoryStore.defaultFileURL) {
        self.fileURL = fileURL
        entries = Self.load(from: fileURL)
    }

    /// `~/Library/Application Support/VideoDownloader/history.json`.
    /// `nonisolated` so it can serve as the `init` default argument (which is
    /// evaluated outside the main actor).
    public nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("VideoDownloader/history.json", isDirectory: false)
    }

    // MARK: - Mutation

    /// Record a completed download: build an entry, prepend it (newest-first),
    /// and persist. Only meaningful for completed items — the caller decides.
    public func record(_ item: DownloadItem, completedAt: Date = Date()) {
        let entry = HistoryEntry(item: item, completedAt: completedAt)
        entries.insert(entry, at: 0)
        persist()
    }

    public func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    public func clear() {
        entries.removeAll()
        persist()
    }

    // MARK: - Persistence

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Tolerant load: a missing or corrupt file yields an empty history.
    private static func load(from url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? makeDecoder().decode([HistoryEntry].self, from: data)
        else { return [] }
        return decoded
    }

    /// Encode on the main actor (fast, in-memory), then hand the resulting `Data`
    /// (Sendable) to a detached task for the blocking directory-create + write, so
    /// the UI never waits on the disk (mirrors `FaviconCache`'s write strategy).
    private func persist() {
        guard let data = try? Self.makeEncoder().encode(entries) else { return }
        let url = fileURL
        writeQueue.async {
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
