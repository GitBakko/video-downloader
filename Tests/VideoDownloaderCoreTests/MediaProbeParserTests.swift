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

    func testSingleVideoMapsVideoOnlyAndAudioOnlyFormats() throws {
        let data = try fixtureData("single_video.json")
        let item = try XCTUnwrap(try MediaProbeParser.items(fromDumpJSON: data).first)

        XCTAssertEqual(item.availableFormats.count, 3)

        // Video-only stream: acodec "none" preserved, resolution derived from
        // height ("1080p"), filesize taken from filesize_approx (no exact filesize).
        let videoOnly = try XCTUnwrap(item.availableFormats.first { $0.formatID == "137" })
        XCTAssertEqual(videoOnly.acodec, "none")
        XCTAssertEqual(videoOnly.vcodec, "avc1.640028")
        XCTAssertEqual(videoOnly.resolution, "1080p")
        XCTAssertEqual(videoOnly.ext, "mp4")
        XCTAssertEqual(videoOnly.filesize, 45678901)   // came from filesize_approx
        XCTAssertEqual(videoOnly.tbr, 2500.0)          // total average bitrate (kbps)

        // Audio-only stream: vcodec "none" preserved, no resolution, exact filesize.
        let audioOnly = try XCTUnwrap(item.availableFormats.first { $0.formatID == "140" })
        XCTAssertEqual(audioOnly.vcodec, "none")
        XCTAssertEqual(audioOnly.acodec, "mp4a.40.2")
        XCTAssertNil(audioOnly.resolution)
        XCTAssertEqual(audioOnly.filesize, 3456789)
        XCTAssertEqual(audioOnly.tbr, 129.5)
    }

    func testAudioOnlyTrackHasNoVideoStreams() throws {
        let data = try fixtureData("audio_only.json")
        let items = try MediaProbeParser.items(fromDumpJSON: data)

        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.title, "Some Music Track")
        XCTAssertFalse(item.availableFormats.isEmpty)
        // Every format is audio-only: vcodec "none", no resolution, no video-less flag on acodec.
        XCTAssertTrue(item.availableFormats.allSatisfy { $0.vcodec == "none" })
        XCTAssertTrue(item.availableFormats.allSatisfy { $0.resolution == nil })
        XCTAssertFalse(item.availableFormats.contains { $0.acodec == "none" })
    }

    func testPlaylistExpandsToOneReadyItemPerEntry() throws {
        let data = try fixtureData("playlist.json")
        let items = try MediaProbeParser.items(fromDumpJSON: data)

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.title), ["First Video", "Second Video", "Third Video"])
        XCTAssertTrue(items.allSatisfy { $0.state == .ready })

        // Each entry keeps its own URL and receives a distinct id.
        XCTAssertEqual(items.map(\.url), [
            "https://www.youtube.com/watch?v=vid001",
            "https://www.youtube.com/watch?v=vid002",
            "https://www.youtube.com/watch?v=vid003"
        ])
        XCTAssertEqual(Set(items.map(\.id)).count, 3)

        // Formats are mapped per entry, including the video-only / audio-only pair.
        let first = try XCTUnwrap(items.first)
        XCTAssertEqual(first.availableFormats.count, 2)
        XCTAssertTrue(first.availableFormats.contains { $0.acodec == "none" })
        XCTAssertTrue(first.availableFormats.contains { $0.vcodec == "none" })
    }

    func testMalformedJSONThrows() {
        let garbage = Data("not json at all".utf8)
        XCTAssertThrowsError(try MediaProbeParser.items(fromDumpJSON: garbage))
    }
}
