import XCTest
@testable import VideoDownloaderCore

final class BinaryInstallPlanTests: XCTestCase {
    let resolver = BinaryURLResolver()
    let layout = BinaryLayout(supportDirectory: URL(fileURLWithPath: "/tmp/AS/VideoDownloader"))

    func test_installTasks_coverAllThreeBinaries_archMatched() {
        let tasks = resolver.installTasks(layout: layout, arch: .arm64)
        XCTAssertEqual(tasks.map { $0.destination.lastPathComponent }, ["yt-dlp", "ffmpeg", "ffprobe"])
        XCTAssertEqual(tasks[1].remote.lastPathComponent, "ffmpeg-darwin-arm64")
        XCTAssertEqual(tasks[2].remote.lastPathComponent, "ffprobe-darwin-arm64")
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
