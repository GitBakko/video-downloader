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

    func test_isTerminal_isTrueOnlyForCompletedFailedCancelled() {
        for state in DownloadState.allCases {
            let expected = (state == .completed || state == .failed || state == .cancelled)
            XCTAssertEqual(state.isTerminal, expected,
                           "\(state) isTerminal should be \(expected)")
        }
    }

    func test_equatable() {
        XCTAssertEqual(DownloadState.downloading, .downloading)
        XCTAssertNotEqual(DownloadState.downloading, .processing)
    }
}
