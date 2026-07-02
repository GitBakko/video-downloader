import XCTest
@testable import VideoDownloaderCore

final class DownloadItemTests: XCTestCase {
    func test_defaults() {
        let item = DownloadItem(url: "https://example.com/v")
        XCTAssertEqual(item.url, "https://example.com/v")
        XCTAssertEqual(item.state, .probing)
        XCTAssertEqual(item.selectedFormat, .video(.best))
        XCTAssertTrue(item.availableFormats.isEmpty)
        XCTAssertNil(item.title)
        XCTAssertNil(item.progress)
    }

    func test_identifiable_usesProvidedID() {
        let id = UUID()
        let item = DownloadItem(id: id, url: "u")
        XCTAssertEqual(item.id, id)
    }

    func test_allowsFormatEditing_mirrorsState() {
        var item = DownloadItem(url: "u", state: .ready)
        XCTAssertTrue(item.allowsFormatEditing)
        item.state = .downloading
        XCTAssertFalse(item.allowsFormatEditing)
    }

    func test_equatable() {
        let id = UUID()
        let a = DownloadItem(id: id, url: "u", state: .ready)
        let b = DownloadItem(id: id, url: "u", state: .ready)
        var c = a
        c.state = .completed
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
