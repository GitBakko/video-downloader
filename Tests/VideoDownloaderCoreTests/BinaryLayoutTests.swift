import XCTest
@testable import VideoDownloaderCore

final class BinaryLayoutTests: XCTestCase {
    let root = URL(fileURLWithPath: "/tmp/AS/VideoDownloader", isDirectory: true)
    var layout: BinaryLayout { BinaryLayout(supportDirectory: root) }

    func test_binDirectory() {
        XCTAssertEqual(layout.binDirectory.path, "/tmp/AS/VideoDownloader/bin")
    }

    func test_binaryPaths() {
        XCTAssertEqual(layout.ytDlpURL.path, "/tmp/AS/VideoDownloader/bin/yt-dlp")
        XCTAssertEqual(layout.ffmpegURL.path, "/tmp/AS/VideoDownloader/bin/ffmpeg")
        XCTAssertEqual(layout.ffprobeURL.path, "/tmp/AS/VideoDownloader/bin/ffprobe")
    }

    // Spec §3.1: managed folder lives under ~/Library/Application Support/VideoDownloader.
    func test_standardLayoutIsUnderApplicationSupport() {
        let l = BinaryLayout.standard()
        XCTAssertTrue(l.supportDirectory.path.hasSuffix("Application Support/VideoDownloader"))
    }
}
