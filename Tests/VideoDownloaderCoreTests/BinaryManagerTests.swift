import XCTest
@testable import VideoDownloaderCore

final class BinaryManagerTests: XCTestCase {
    func test_exposesInjectedLayoutPaths_andStartsWithNoVersion() {
        let root = URL(fileURLWithPath: "/tmp/AS/VideoDownloader")
        let manager = BinaryManager(layout: BinaryLayout(supportDirectory: root), arch: .x86_64)
        XCTAssertEqual(manager.ytDlpURL.path, "/tmp/AS/VideoDownloader/bin/yt-dlp/yt-dlp_macos")
        XCTAssertEqual(manager.ffmpegDirectory.path, "/tmp/AS/VideoDownloader/bin")
        XCTAssertNil(manager.ytDlpVersion)
    }

    func test_conformsToBinaryProviding() {
        let manager: BinaryProviding = BinaryManager(layout: .standard())
        XCTAssertNil(manager.ytDlpVersion)
    }
}
