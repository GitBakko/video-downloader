/// A single downloadable stream reported by yt-dlp for a media URL (spec §4).
public struct MediaFormat: Identifiable, Equatable, Sendable {
    public var formatID: String
    public var resolution: String?
    public var ext: String
    public var vcodec: String?
    public var acodec: String?
    public var filesize: Int64?
    /// Total average bitrate in kbps, as reported by yt-dlp (`tbr`). `nil` when unknown.
    public var tbr: Double?
    public var note: String?

    /// `Identifiable` id backed by yt-dlp's stable `format_id`.
    public var id: String { formatID }

    public init(
        formatID: String,
        resolution: String? = nil,
        ext: String,
        vcodec: String? = nil,
        acodec: String? = nil,
        filesize: Int64? = nil,
        tbr: Double? = nil,
        note: String? = nil
    ) {
        self.formatID = formatID
        self.resolution = resolution
        self.ext = ext
        self.vcodec = vcodec
        self.acodec = acodec
        self.filesize = filesize
        self.tbr = tbr
        self.note = note
    }

    /// A video-only stream (no audio track): yt-dlp reports `acodec == "none"`.
    /// The argument builder adds `+bestaudio` for these so no muted files appear.
    public var isVideoOnly: Bool { acodec == "none" }

    /// An audio-only stream: yt-dlp reports `vcodec == "none"`.
    public var isAudioOnly: Bool { vcodec == "none" }
}
