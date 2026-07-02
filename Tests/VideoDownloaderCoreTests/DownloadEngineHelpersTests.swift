import XCTest
@testable import VideoDownloaderCore

final class DownloadEngineHelpersTests: XCTestCase {

    func test_destination_parsesDownloadDestinationLine() {
        let url = DownloadEngine.destination(from: "[download] Destination: /Users/x/Movies/Song.mp4")
        XCTAssertEqual(url, URL(fileURLWithPath: "/Users/x/Movies/Song.mp4"))
    }

    func test_destination_parsesExtractAudioDestinationLine() {
        let url = DownloadEngine.destination(from: "[ExtractAudio] Destination: /Users/x/Movies/Song.mp3")
        XCTAssertEqual(url, URL(fileURLWithPath: "/Users/x/Movies/Song.mp3"))
    }

    func test_destination_parsesMergerLine() {
        let url = DownloadEngine.destination(from: #"[Merger] Merging formats into "/Users/x/Movies/Clip.mkv""#)
        XCTAssertEqual(url, URL(fileURLWithPath: "/Users/x/Movies/Clip.mkv"))
    }

    func test_destination_parsesAlreadyDownloadedLine() {
        let url = DownloadEngine.destination(from: "[download] /Users/x/Movies/Clip.mp4 has already been downloaded")
        XCTAssertEqual(url, URL(fileURLWithPath: "/Users/x/Movies/Clip.mp4"))
    }

    func test_destination_returnsNilForProgressLine() {
        XCTAssertNil(DownloadEngine.destination(from: " 42.0%|4.20MiB/s|00:12"))
    }
}
