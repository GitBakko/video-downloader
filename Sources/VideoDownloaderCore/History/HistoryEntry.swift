import Foundation

/// A persisted record of one successful download, shown in the history window.
///
/// Independent of `DownloadItem` (which is queue-only and non-`Codable`) so the
/// on-disk format stays stable even as the queue model evolves. Only completed
/// downloads become entries — the caller (`HistoryStore.record`) decides when.
public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: String
    public var title: String?
    /// yt-dlp extractor key (e.g. "Youtube") — drives the source filter + badge.
    public var source: String?
    /// Thumbnail URL as a string (kept `Codable`-friendly).
    public var thumbnail: String?
    /// Short, human-readable description of the format the user downloaded.
    public var formatSummary: String
    /// Absolute path of the produced file, when known.
    public var outputPath: String?
    /// When the item entered the queue.
    public var addedAt: Date
    /// When the download finished.
    public var completedAt: Date

    public init(
        id: UUID = UUID(),
        url: String,
        title: String? = nil,
        source: String? = nil,
        thumbnail: String? = nil,
        formatSummary: String,
        outputPath: String? = nil,
        addedAt: Date,
        completedAt: Date
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.source = source
        self.thumbnail = thumbnail
        self.formatSummary = formatSummary
        self.outputPath = outputPath
        self.addedAt = addedAt
        self.completedAt = completedAt
    }

    /// Build an entry from a completed `DownloadItem`. `completedAt` defaults to
    /// now (the queue records at the moment the item reaches `.completed`).
    public init(item: DownloadItem, completedAt: Date = Date()) {
        self.init(
            id: item.id,
            url: item.url,
            title: item.title,
            source: item.source,
            thumbnail: item.thumbnailURL?.absoluteString,
            formatSummary: HistoryEntry.summary(for: item.selectedFormat),
            outputPath: item.outputPath?.path,
            addedAt: item.addedAt,
            completedAt: completedAt
        )
    }

    /// Host of `url`, for the favicon (mirrors the queue's source badge).
    public var host: String? {
        URL(string: url)?.host
    }

    /// Short label for a `FormatChoice`, e.g. "Video · Migliore", "Audio MP3",
    /// or "Formato 137".
    static func summary(for choice: FormatChoice) -> String {
        switch choice {
        case .video(let quality):
            return "Video · \(videoQualityLabel(quality))"
        case .audio:
            return "Audio MP3"
        case .specific(let id):
            return "Formato \(id)"
        }
    }

    private static func videoQualityLabel(_ quality: VideoQuality) -> String {
        switch quality {
        case .best:  return "Migliore"
        case .p1080: return "1080p"
        case .p720:  return "720p"
        case .p480:  return "480p"
        }
    }
}
