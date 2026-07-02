import Foundation

/// User-configurable download settings passed to `ArgumentBuilder` (spec shared interface).
public struct DownloadSettings: Equatable {
    /// Destination folder for finished files.
    public var destination: URL
    /// When true, yt-dlp is asked to embed cover art + metadata.
    public var embedThumbnailAndMetadata: Bool

    public init(destination: URL, embedThumbnailAndMetadata: Bool) {
        self.destination = destination
        self.embedThumbnailAndMetadata = embedThumbnailAndMetadata
    }
}
