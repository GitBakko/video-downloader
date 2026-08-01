import XCTest
@testable import VideoDownloaderCore

final class YtDlpMessageTests: XCTestCase {

    func test_ageGatedTweet_pointsAtTheCookiesSetting() {
        let mapped = YtDlpMessage.explain(
            "ERROR: [twitter] 2082428925922136202: No video could be found in this tweet")
        XCTAssertTrue(mapped.contains("Impostazioni"), mapped)
        XCTAssertFalse(mapped.contains("No video could be found"), mapped)
    }

    func test_staleCookies_doNotTellTheUserToFileABug() {
        let mapped = YtDlpMessage.explain(
            "ERROR: [twitter] 123: Could not authenticate you; please report this issue on github")
        XCTAssertFalse(mapped.contains("github"), mapped)
        XCTAssertTrue(mapped.contains("login"), mapped)
    }

    func test_unrelatedErrors_passThroughUntouched() {
        let line = "ERROR: Video unavailable"
        XCTAssertEqual(YtDlpMessage.explain(line), line)
    }
}
