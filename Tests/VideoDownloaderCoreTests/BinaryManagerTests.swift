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

    // MARK: - M3/S18: localized error descriptions

    func test_downloadFailed_hasLocalizedDescription() {
        let error = BinaryManagerError.downloadFailed(
            url: URL(string: "https://example.com/dl/yt-dlp_macos.zip")!, status: 404)
        XCTAssertEqual(
            error.errorDescription,
            "Impossibile scaricare yt-dlp_macos.zip (HTTP 404). Controlla la connessione e riprova.")
    }

    func test_extractionFailed_hasLocalizedDescription() {
        let error = BinaryManagerError.extractionFailed(tool: "yt-dlp", exitCode: 2)
        XCTAssertEqual(error.errorDescription, "Estrazione di yt-dlp fallita (codice 2).")
    }
}
