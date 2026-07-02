import XCTest
@testable import VideoDownloaderCore

final class ProgressParserTests: XCTestCase {

    // MARK: - Assertion helpers

    private func assertProgress(
        _ raw: String,
        percent expectedPercent: Double?,
        speed expectedSpeed: String?,
        eta expectedETA: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .progress(percent, speed, eta, stage)? = ProgressParser.parse(line: raw) else {
            return XCTFail("expected .progress for \(raw)", file: file, line: line)
        }
        if let expectedPercent {
            guard let percent else {
                return XCTFail("expected percent \(expectedPercent), got nil", file: file, line: line)
            }
            XCTAssertEqual(percent, expectedPercent, accuracy: 0.0001, file: file, line: line)
        } else {
            XCTAssertNil(percent, "expected nil percent for \(raw)", file: file, line: line)
        }
        XCTAssertEqual(speed, expectedSpeed, file: file, line: line)
        XCTAssertEqual(eta, expectedETA, file: file, line: line)
        XCTAssertNil(stage, "parser must not label the pass; stage is nil", file: file, line: line)
    }

    private func assertIgnored(_ raw: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(ProgressParser.parse(line: raw), "expected nil for \(raw)", file: file, line: line)
    }

    // MARK: - 4.1 Standard progress line

    func testParsesStandardProgressLine() {
        assertProgress(
            " 12.3%|  4.20MiB/s|00:38",
            percent: 0.123,
            speed: "4.20MiB/s",
            eta: "00:38"
        )
    }

    func testProgressStageIsNil() {
        guard case let .progress(_, _, _, stage)? =
            ProgressParser.parse(line: " 1.0%|1.00MiB/s|10:00") else {
            return XCTFail("expected .progress")
        }
        XCTAssertNil(stage)   // parser does not label the pass; UI derives label from state
    }

    func testIgnoresNonMatchingLines() {
        assertIgnored("some random yt-dlp log line")
        assertIgnored("")
        assertIgnored("downloading: 1 of 3")        // not a 3-field pipe body
        assertIgnored("12.3%|1.00MiB/s")             // only 2 fields, not 3
    }
}
