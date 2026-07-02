import XCTest
@testable import VideoDownloaderCore

final class FormatChoiceTests: XCTestCase {
    func test_isAudioOnly() {
        XCTAssertTrue(FormatChoice.audio(.best).isAudioOnly)
        XCTAssertFalse(FormatChoice.video(.best).isAudioOnly)
        XCTAssertFalse(FormatChoice.specific(formatID: "140").isAudioOnly)
    }

    func test_specificFormatID() {
        XCTAssertEqual(FormatChoice.specific(formatID: "140").specificFormatID, "140")
        XCTAssertNil(FormatChoice.video(.p720).specificFormatID)
        XCTAssertNil(FormatChoice.audio(.best).specificFormatID)
    }

    func test_equatable() {
        XCTAssertEqual(FormatChoice.video(.best), .video(.best))
        XCTAssertNotEqual(FormatChoice.video(.best), .video(.p720))
        XCTAssertEqual(FormatChoice.specific(formatID: "22"), .specific(formatID: "22"))
        XCTAssertNotEqual(FormatChoice.specific(formatID: "22"), .specific(formatID: "18"))
        XCTAssertNotEqual(FormatChoice.audio(.best), .video(.best))
    }

    func test_videoQuality_allCases() {
        XCTAssertEqual(VideoQuality.allCases, [.best, .p1080, .p720, .p480])
    }
}
