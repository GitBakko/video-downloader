import XCTest
@testable import VideoDownloaderCore

final class MediaFormatTests: XCTestCase {
    func test_id_equalsFormatID() {
        let f = MediaFormat(formatID: "137", ext: "mp4")
        XCTAssertEqual(f.id, "137")
    }

    func test_isVideoOnly_whenAcodecIsNone() {
        let videoOnly = MediaFormat(formatID: "137", ext: "mp4", vcodec: "avc1", acodec: "none")
        let muxed = MediaFormat(formatID: "22", ext: "mp4", vcodec: "avc1", acodec: "mp4a")
        XCTAssertTrue(videoOnly.isVideoOnly)
        XCTAssertFalse(muxed.isVideoOnly)
    }

    func test_isAudioOnly_whenVcodecIsNone() {
        let audioOnly = MediaFormat(formatID: "140", ext: "m4a", vcodec: "none", acodec: "mp4a")
        let muxed = MediaFormat(formatID: "22", ext: "mp4", vcodec: "avc1", acodec: "mp4a")
        XCTAssertTrue(audioOnly.isAudioOnly)
        XCTAssertFalse(muxed.isAudioOnly)
    }

    func test_equatable() {
        let a = MediaFormat(formatID: "137", resolution: "1080p", ext: "mp4",
                            vcodec: "avc1", acodec: "none", filesize: 1024, note: "1080p")
        let b = MediaFormat(formatID: "137", resolution: "1080p", ext: "mp4",
                            vcodec: "avc1", acodec: "none", filesize: 1024, note: "1080p")
        let c = MediaFormat(formatID: "18", ext: "mp4")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
