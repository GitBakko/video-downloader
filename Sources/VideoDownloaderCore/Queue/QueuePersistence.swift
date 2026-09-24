import Foundation

/// Codable snapshot of one queue item's durable fields, so the whole download
/// list survives a quit and reappears next launch — the user resumes whatever
/// they want (interrupted downloads come back `.ready`, not auto-started).
///
/// Kept separate from `DownloadItem` (queue-only, non-`Codable`) so the on-disk
/// format stays stable as the queue model evolves — same split as `HistoryEntry`.
/// The live fields (`progress`/`speed`/`eta`/`stage`) and the re-probable
/// `availableFormats` are intentionally not stored: they're transient.
public struct QueueSnapshotItem: Codable, Equatable, Sendable {
    public var id: UUID
    public var url: String
    public var title: String?
    public var thumbnail: String?
    public var duration: TimeInterval?
    public var source: String?
    public var mediaID: String?
    /// Selected format encoded to a string (FormatChoice isn't Codable).
    public var formatToken: String
    public var state: DownloadState
    public var outputPath: String?
    public var errorMessage: String?
    public var addedAt: Date
    /// Optional, so a `queue.json` written before this field existed still decodes.
    public var playlistIndex: Int?
    /// Naming metadata (see `FileNamer`); optional for older snapshots.
    public var description: String?
    public var uploader: String?
    public var cast: [String]?

    public init(item: DownloadItem) {
        playlistIndex = item.playlistIndex
        description = item.description
        uploader = item.uploader
        cast = item.cast.isEmpty ? nil : item.cast
        id = item.id
        url = item.url
        title = item.title
        thumbnail = item.thumbnailURL?.absoluteString
        duration = item.duration
        source = item.source
        mediaID = item.mediaID
        formatToken = SettingsStore.encode(item.selectedFormat)
        state = item.state
        outputPath = item.outputPath?.path
        errorMessage = item.errorMessage
        addedAt = item.addedAt
    }

    /// Rebuild a queue item, normalizing any in-flight state to `.ready` (see
    /// `DownloadState.restoredAcrossLaunch`). `availableFormats` is empty — the
    /// saved `selectedFormat` is enough to resume; yt-dlp re-resolves it.
    public func toItem() -> DownloadItem {
        DownloadItem(
            id: id,
            url: url,
            title: title,
            thumbnailURL: thumbnail.flatMap { URL(string: $0) },
            duration: duration,
            source: source,
            mediaID: mediaID,
            description: description,
            uploader: uploader,
            cast: cast ?? [],
            availableFormats: [],
            selectedFormat: SettingsStore.decode(formatToken) ?? .video(.best),
            state: state.restoredAcrossLaunch,
            outputPath: outputPath.map { URL(fileURLWithPath: $0) },
            errorMessage: errorMessage,
            addedAt: addedAt,
            playlistIndex: playlistIndex)
    }
}
