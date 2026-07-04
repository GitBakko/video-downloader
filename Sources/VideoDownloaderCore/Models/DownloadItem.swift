import Foundation

/// The unit of work in the download queue (spec §4). A playlist probe expands
/// into many of these, all starting in `.probing`/`.ready`.
public struct DownloadItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: String
    public var title: String?
    public var thumbnailURL: URL?
    public var duration: TimeInterval?
    /// yt-dlp extractor key (e.g. "Youtube", "Vimeo"); drives the source badge in the UI.
    public var source: String?
    /// yt-dlp's own media id (from the probe). It appears in the output filename
    /// (`%(title)s [%(id)s].%(ext)s`), so it links a resumed/interrupted download
    /// to its leftover `.part`/`.ytdl` files on disk.
    public var mediaID: String?
    public var availableFormats: [MediaFormat]
    public var selectedFormat: FormatChoice
    public var state: DownloadState
    public var stage: String?
    public var progress: Double?
    public var speed: String?
    public var eta: String?
    public var outputPath: URL?
    public var errorMessage: String?
    /// When the item entered the queue. Used by the download history as the
    /// "added" date; defaults to now at creation. Trailing (with a default) so
    /// every existing call site keeps compiling.
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        url: String,
        title: String? = nil,
        thumbnailURL: URL? = nil,
        duration: TimeInterval? = nil,
        source: String? = nil,
        mediaID: String? = nil,
        availableFormats: [MediaFormat] = [],
        selectedFormat: FormatChoice = .video(.best),
        state: DownloadState = .probing,
        stage: String? = nil,
        progress: Double? = nil,
        speed: String? = nil,
        eta: String? = nil,
        outputPath: URL? = nil,
        errorMessage: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.source = source
        self.mediaID = mediaID
        self.availableFormats = availableFormats
        self.selectedFormat = selectedFormat
        self.state = state
        self.stage = stage
        self.progress = progress
        self.speed = speed
        self.eta = eta
        self.outputPath = outputPath
        self.errorMessage = errorMessage
        self.addedAt = addedAt
    }

    /// Convenience mirror of `state.allowsFormatEditing` used by the queue/UI.
    public var allowsFormatEditing: Bool { state.allowsFormatEditing }

    /// True when a field the on-disk queue snapshot persists differs from `other`.
    /// Excludes the live `progress`/`speed`/`eta`/`stage` (which change ~10-20/s
    /// during a download) so those hot-path updates never trigger a queue re-save.
    func durablyDiffers(from other: DownloadItem) -> Bool {
        state != other.state
            || selectedFormat != other.selectedFormat
            || outputPath != other.outputPath
            || errorMessage != other.errorMessage
            || title != other.title
            || url != other.url
            || mediaID != other.mediaID
            || source != other.source
            || thumbnailURL != other.thumbnailURL
            || duration != other.duration
    }
}
