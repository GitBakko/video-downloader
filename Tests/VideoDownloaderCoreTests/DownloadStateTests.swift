import XCTest
@testable import VideoDownloaderCore

final class DownloadStateTests: XCTestCase {
    func test_allowsFormatEditing_isTrueOnlyForReadyAndQueued() {
        for state in DownloadState.allCases {
            let expected = (state == .ready || state == .queued)
            XCTAssertEqual(state.allowsFormatEditing, expected,
                           "\(state) allowsFormatEditing should be \(expected)")
        }
    }
}
