import XCTest
@testable import VideoDownloaderCore

final class BinaryInstallPlanTests: XCTestCase {
    let resolver = BinaryURLResolver()
    let layout = BinaryLayout(supportDirectory: URL(fileURLWithPath: "/tmp/AS/VideoDownloader"))

    func test_installTasks_coverAllThreeBinaries_archMatched() {
        let tasks = resolver.installTasks(layout: layout, arch: .arm64)
        // yt-dlp's destination is the inner executable produced by extraction.
        XCTAssertEqual(
            tasks.map { $0.destination.lastPathComponent },
            ["yt-dlp_macos", "ffmpeg", "ffprobe"]
        )
        XCTAssertEqual(tasks[1].remote.lastPathComponent, "ffmpeg-darwin-arm64")
        XCTAssertEqual(tasks[2].remote.lastPathComponent, "ffprobe-darwin-arm64")
    }

    // yt-dlp's remote is the onedir zip and it carries an extraction directory;
    // ffmpeg/ffprobe are plain single-file downloads with no extraction.
    func test_installTasks_ytDlpTaskIsAnExtractedZip() {
        let tasks = resolver.installTasks(layout: layout, arch: .arm64)
        XCTAssertEqual(tasks[0].remote.lastPathComponent, "yt-dlp_macos.zip")
        XCTAssertEqual(tasks[0].destination.path, "/tmp/AS/VideoDownloader/bin/yt-dlp/yt-dlp_macos")
        XCTAssertEqual(tasks[0].extractDirectory?.path, "/tmp/AS/VideoDownloader/bin/yt-dlp")
        XCTAssertNil(tasks[1].extractDirectory)
        XCTAssertNil(tasks[2].extractDirectory)
    }

    func test_pendingTasks_skipsAlreadyInstalled() {
        let tasks = resolver.installTasks(layout: layout, arch: .x86_64)
        let installed: Set<String> = [layout.ytDlpURL.path, layout.ffmpegURL.path]
        let pending = pendingBinaryTasks(tasks) { installed.contains($0.path) }
        XCTAssertEqual(pending.map { $0.destination.lastPathComponent }, ["ffprobe"])
    }

    func test_pendingTasks_emptyWhenAllInstalled() {
        let tasks = resolver.installTasks(layout: layout, arch: .x86_64)
        let pending = pendingBinaryTasks(tasks) { _ in true }
        XCTAssertTrue(pending.isEmpty)
    }
}
