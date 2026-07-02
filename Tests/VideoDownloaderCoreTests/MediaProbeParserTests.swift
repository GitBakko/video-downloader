import XCTest
@testable import VideoDownloaderCore

final class MediaProbeParserTests: XCTestCase {
    /// Loads a fixture that lives next to this test file. We resolve the path
    /// from `#filePath` (rather than `Bundle.module`) so we don't have to touch
    /// the Phase-1-owned Package.swift to register test resources.
    private func fixtureData(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    func testSingleVideoProducesOneReadyItem() throws {
        let data = try fixtureData("single_video.json")
        let items = try MediaProbeParser.items(fromDumpJSON: data)

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.title, "Rick Astley - Never Gonna Give You Up")
        XCTAssertEqual(item.url, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(item.duration, 213.0)
        XCTAssertEqual(item.thumbnailURL,
                       URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"))
        XCTAssertEqual(item.state, .ready)  // DownloadState is a payload-free enum ⇒ Equatable
    }
}
