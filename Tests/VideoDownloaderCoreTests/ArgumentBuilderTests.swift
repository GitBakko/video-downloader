import XCTest
import Foundation
@testable import VideoDownloaderCore

final class ArgumentBuilderTests: XCTestCase {

    // MARK: - Fixed inputs

    private let destination = URL(fileURLWithPath: "/Users/tester/Movies/VD", isDirectory: true)
    private let ffmpegDir = URL(fileURLWithPath: "/opt/vd/bin", isDirectory: true)

    private let outputTemplate = "/Users/tester/Movies/VD/%(title)s [%(id)s].%(ext)s"
    private let progressTemplate =
        "%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"

    // MARK: - Helpers

    private func settings(embed: Bool = false) -> DownloadSettings {
        DownloadSettings(destination: destination, embedThumbnailAndMetadata: embed)
    }

    private func item(formats: [MediaFormat] = []) -> DownloadItem {
        DownloadItem(
            id: UUID(),
            url: "https://example.com/watch?v=abc",
            title: "Sample",
            thumbnailURL: nil,
            duration: nil,
            availableFormats: formats,
            selectedFormat: .video(.best),
            state: .ready,
            stage: nil,
            progress: nil,
            speed: nil,
            eta: nil,
            outputPath: nil,
            errorMessage: nil
        )
    }

    /// The trailing common-flag block shared by every case (spec §6).
    private func commonTail(embed: Bool = false) -> [String] {
        var tail = [
            "--ffmpeg-location", "/opt/vd/bin",
            "-o", outputTemplate,
            "--newline",
            "--progress-template", progressTemplate,
        ]
        if embed { tail += ["--embed-thumbnail", "--embed-metadata"] }
        return tail
    }

    // MARK: - .video(.best)

    func test_video_best() {
        let args = ArgumentBuilder.downloadArguments(
            for: .video(.best),
            item: item(),
            settings: settings(),
            ffmpegDirectory: ffmpegDir
        )

        XCTAssertEqual(
            args,
            ["-f", "bv*+ba/b", "--merge-output-format", "mp4", "--remux-video", "mp4"]
                + commonTail()
        )
    }

    // MARK: - .video capped resolutions

    func test_video_p1080() {
        let args = ArgumentBuilder.downloadArguments(
            for: .video(.p1080),
            item: item(),
            settings: settings(),
            ffmpegDirectory: ffmpegDir
        )
        XCTAssertEqual(
            args,
            ["-f", "bv*[height<=1080]+ba/b[height<=1080]",
             "--merge-output-format", "mp4", "--remux-video", "mp4"]
                + commonTail()
        )
    }

    func test_video_p720() {
        let args = ArgumentBuilder.downloadArguments(
            for: .video(.p720),
            item: item(),
            settings: settings(),
            ffmpegDirectory: ffmpegDir
        )
        XCTAssertEqual(
            args,
            ["-f", "bv*[height<=720]+ba/b[height<=720]",
             "--merge-output-format", "mp4", "--remux-video", "mp4"]
                + commonTail()
        )
    }

    func test_video_p480() {
        let args = ArgumentBuilder.downloadArguments(
            for: .video(.p480),
            item: item(),
            settings: settings(),
            ffmpegDirectory: ffmpegDir
        )
        XCTAssertEqual(
            args,
            ["-f", "bv*[height<=480]+ba/b[height<=480]",
             "--merge-output-format", "mp4", "--remux-video", "mp4"]
                + commonTail()
        )
    }

    // MARK: - .audio(.best)

    func test_audio_best_extractsMp3_noRemux() {
        let args = ArgumentBuilder.downloadArguments(
            for: .audio(.best),
            item: item(),
            settings: settings(),
            ffmpegDirectory: ffmpegDir
        )
        XCTAssertEqual(
            args,
            ["-f", "ba/b", "-x", "--audio-format", "mp3"] + commonTail()
        )
        // Audio must NOT carry the video merge/remux flags.
        XCTAssertFalse(args.contains("--remux-video"))
        XCTAssertFalse(args.contains("--merge-output-format"))
    }
}
