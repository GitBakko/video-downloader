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
            // v1: MP3 best only.
            args += ["-f", "ba/b", "-x", "--audio-format", "mp3"]
        case .specific(let formatID):
            let isVideoOnly = item.availableFormats
                .first { $0.formatID == formatID }?
                .isVideoOnly ?? false
            if isVideoOnly {
                args += ["-f", "\(formatID)+bestaudio"]
                args += ["--merge-output-format", "mp4", "--remux-video", "mp4"]
            } else {
                args += ["-f", formatID]
            }
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
            "download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
        ]

        if settings.embedThumbnailAndMetadata {
            args += ["--embed-thumbnail", "--embed-metadata"]
        }

        return args
    }

    private static func videoSelector(for quality: VideoQuality) -> String {
        switch quality {
        case .best:  return "bv*+ba/b"
        case .p1080: return "bv*[height<=1080]+ba/b[height<=1080]"
        case .p720:  return "bv*[height<=720]+ba/b[height<=720]"
        case .p480:  return "bv*[height<=480]+ba/b[height<=480]"
        }
    }
}
