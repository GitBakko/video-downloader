import Foundation

/// Builds the yt-dlp argument vector for a given `FormatChoice`, per design spec §6.
/// Pure function: no I/O. Fully covered by `ArgumentBuilderTests`.
enum ArgumentBuilder {
    static func downloadArguments(
        for choice: FormatChoice,
        item: DownloadItem,
        settings: DownloadSettings,
        ffmpegDirectory: URL
    ) -> [String] {
        var args: [String] = []

        switch choice {
        case .video(let quality):
            args += ["-f", videoSelector(for: quality)]
            args += ["--merge-output-format", "mp4", "--remux-video", "mp4"]
        case .audio:
            args += ["-f", "ba/b"]              // refined in Task 3.4
        case .specific(let formatID):
            args += ["-f", formatID]            // refined in Task 3.5
        }

        // Common flags (spec §6). Fixed order → deterministic argument vectors.
        args += ["--ffmpeg-location", ffmpegDirectory.path]
        let outputTemplate = settings.destination
            .appendingPathComponent("%(title)s [%(id)s].%(ext)s")
            .path
        args += ["-o", outputTemplate]
        args += ["--newline"]
        args += [
            "--progress-template",
            "%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
        ]

        return args
    }

    private static func videoSelector(for quality: VideoQuality) -> String {
        switch quality {
        case .best: return "bv*+ba/b"
        default:    return "bv*+ba/b"           // refined in Task 3.3
        }
    }
}
