import Foundation

/// Turns a raw `yt-dlp -J` JSON dump into `[DownloadItem]`.
/// Pure logic (no Process/network/filesystem) ⇒ fully unit-tested.
public enum MediaProbeParser {
    /// Parses the JSON produced by `yt-dlp -J --no-warnings <url>`.
    /// A single video yields one `.ready` item; a playlist yields one
    /// `.ready` item per entry (added in a later task).
    public static func items(fromDumpJSON data: Data) throws -> [DownloadItem] {
        let info = try JSONDecoder().decode(YtDlpInfo.self, from: data)
        return [makeItem(from: info)]
    }

    private static func makeItem(from info: YtDlpInfo) -> DownloadItem {
        DownloadItem(
            id: UUID(),
            url: info.webpageURL ?? info.url ?? "",
            title: info.title,
            thumbnailURL: info.thumbnail.flatMap { URL(string: $0) },
            duration: info.duration,
            availableFormats: [],
            selectedFormat: .video(.best),   // neutral default; QueueStore.add applies the real default
            state: .ready,
            stage: nil,
            progress: nil,
            speed: nil,
            eta: nil,
            outputPath: nil,
            errorMessage: nil
        )
    }
}
