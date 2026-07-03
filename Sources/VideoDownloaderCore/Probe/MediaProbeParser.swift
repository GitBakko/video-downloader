import Foundation

/// Turns a raw `yt-dlp -J` JSON dump into `[DownloadItem]`.
/// Pure logic (no Process/network/filesystem) ⇒ fully unit-tested.
public enum MediaProbeParser {
    /// Parses the JSON produced by `yt-dlp -J --no-warnings <url>`.
    /// A single video yields one `.ready` item; a playlist yields one
    /// `.ready` item per entry (added in a later task).
    public static func items(fromDumpJSON data: Data) throws -> [DownloadItem] {
        let info = try JSONDecoder().decode(YtDlpInfo.self, from: data)
        if info.type == "playlist", let entries = info.entries {
            // Skip `null` entries (unavailable/private videos) so one dead video
            // never fails the whole probe → one .ready item per surviving entry.
            return entries.compactMap { $0 }.map { makeItem(from: $0) }
        }
        return [makeItem(from: info)]
    }

    private static func makeItem(from info: YtDlpInfo) -> DownloadItem {
        DownloadItem(
            id: UUID(),
            url: info.webpageURL ?? info.url ?? "",
            title: info.title,
            thumbnailURL: info.thumbnail.flatMap { URL(string: $0) },
            duration: info.duration,
            source: info.extractorKey,
            availableFormats: (info.formats ?? []).map(mapFormat),
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

    private static func mapFormat(_ f: YtDlpFormat) -> MediaFormat {
        MediaFormat(
            formatID: f.formatID,
            resolution: f.height.map { "\($0)p" },   // 1080 → "1080p"; nil ⇒ nil (audio)
            ext: f.ext,
            vcodec: f.vcodec,                          // "none" preserved
            acodec: f.acodec,                          // "none" preserved
            filesize: f.filesize ?? f.filesizeApprox,  // exact, else approximate
            tbr: f.tbr,                                // total average bitrate (kbps)
            note: f.formatNote
        )
    }
}
