import Foundation

/// User-configurable download settings passed to `ArgumentBuilder` (spec shared interface).
public struct DownloadSettings: Equatable {
    /// Destination folder for finished files.
    public var destination: URL
    /// When true, yt-dlp is asked to embed cover art + metadata.
    public var embedThumbnailAndMetadata: Bool
    /// Browser to borrow login cookies from (`--cookies-from-browser`), or nil
    /// for anonymous requests. See `ArgumentBuilder.cookieArguments`.
    public var cookiesBrowser: String?

    public init(destination: URL, embedThumbnailAndMetadata: Bool, cookiesBrowser: String? = nil) {
        self.destination = destination
        self.embedThumbnailAndMetadata = embedThumbnailAndMetadata
        self.cookiesBrowser = cookiesBrowser
    }
}
