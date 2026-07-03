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
    public var availableFormats: [MediaFormat]
    public var selectedFormat: FormatChoice
    public var state: DownloadState
    public var stage: String?
    public var progress: Double?
    public var speed: String?
    public var eta: String?
    public var outputPath: URL?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        url: String,
        title: String? = nil,
        thumbnailURL: URL? = nil,
        duration: TimeInterval? = nil,
        source: String? = nil,
        availableFormats: [MediaFormat] = [],
        selectedFormat: FormatChoice = .video(.best),
        state: DownloadState = .probing,
        stage: String? = nil,
        progress: Double? = nil,
        speed: String? = nil,
        eta: String? = nil,
        outputPath: URL? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.source = source
        self.availableFormats = availableFormats
        self.selectedFormat = selectedFormat
        self.state = state
        self.stage = stage
        self.progress = progress
        self.speed = speed
        self.eta = eta
        self.outputPath = outputPath
        self.errorMessage = errorMessage
    }

    /// Convenience mirror of `state.allowsFormatEditing` used by the queue/UI.
    public var allowsFormatEditing: Bool { state.allowsFormatEditing }
}
