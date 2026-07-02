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

    // MARK: - 4.2 Unknown / unavailable values → nil

    func testMapsUnknownValuesToNil() {
        assertProgress(
            "  N/A%|Unknown B/s|Unknown",
            percent: nil,
            speed: nil,
            eta: nil
        )
    }

    func testMapsDashesToNilButKeepsPercent() {
        assertProgress(
            "  0.0%|---|---",
            percent: 0.0,
            speed: nil,
            eta: nil
        )
    }

    func testBareNAValuesAreNil() {
        assertProgress(
            "  5.0%|  N/A|  N/A",
            percent: 0.05,
            speed: nil,
            eta: nil
        )
    }

    // MARK: - 4.3 Whitespace / carriage-return / newline tolerance

    func testTrimsLeadingWhitespaceAndTrailingCarriageReturn() {
        assertProgress(
            "   5.0%|  N/A|00:12\r",
            percent: 0.05,
            speed: nil,
            eta: "00:12"
        )
    }

    func testTrimsTrailingNewline() {
        assertProgress(
            " 5.0%|1.00MiB/s|00:12\n",
            percent: 0.05,
            speed: "1.00MiB/s",
            eta: "00:12"
        )
    }

    private func assertProcessing(_ raw: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .processing? = ProgressParser.parse(line: raw) else {
            return XCTFail("expected .processing for \(raw)", file: file, line: line)
        }
    }

    // MARK: - 4.4 Post-processing indicators

    func testRecognisesPostProcessingLines() {
        assertProcessing("[Merger] Merging formats into \"out.mp4\"")
        assertProcessing("[ExtractAudio] Destination: song.mp3")
        assertProcessing("[VideoRemuxer] Remuxing video from mp4 to mp4")
        assertProcessing("[EmbedThumbnail] ffmpeg: embedding thumbnail in \"out.mp4\"")
        assertProcessing("[Metadata] Adding metadata to \"out.mp4\"")
    }

    func testIsPostProcessingHelper() {
        XCTAssertTrue(ProgressParser.isPostProcessing("[Merger] Merging formats"))
        XCTAssertTrue(ProgressParser.isPostProcessing("   [ExtractAudio] Destination: song.mp3"))
        XCTAssertFalse(ProgressParser.isPostProcessing(" 12.3%|4.20MiB/s|00:38"))
        XCTAssertFalse(ProgressParser.isPostProcessing("some random line"))
    }

    func testProgressLineIsNotPostProcessing() {
        // Regression: a progress line must still parse as .progress.
        assertProgress(" 50.0%|2.00MiB/s|00:05",
                       percent: 0.5, speed: "2.00MiB/s", eta: "00:05")
    }

    // MARK: - 4.5 Percent clamped to 0…1 + realistic multi-line sequence

    func testClampsOutOfRangePercent() {
        assertProgress("150.0%|1.00MiB/s|00:00",
                       percent: 1.0, speed: "1.00MiB/s", eta: "00:00")
    }

    func testParsesRealisticTwoPassSequence() {
        // A `bv*+ba` download: video pass, audio pass, then merge + embed.
        let log = [
            "   0.0%|Unknown B/s|Unknown",                                // video pass starts
            "  42.1%|  3.10MiB/s|00:12",
            " 100.0%|  4.00MiB/s|00:00",                                  // video pass done
            "   0.0%|Unknown B/s|Unknown",                                // audio pass starts
            "  88.0%|  1.20MiB/s|00:01",
            " 100.0%|  1.30MiB/s|00:00",                                  // audio pass done
            "[Merger] Merging formats into \"out.mp4\"",                  // processing
            "[EmbedThumbnail] ffmpeg: embedding thumbnail in \"out.mp4\"",
            "[deleting original file out.f137.mp4 (pass -k to keep)]"     // ignored → nil
        ]
        let events = log.map { ProgressParser.parse(line: $0) }

        let progressCount = events.filter { if case .progress = $0 { return true } else { return false } }.count
        let processingCount = events.filter { if case .processing = $0 { return true } else { return false } }.count
        let ignoredCount = events.filter { $0 == nil }.count

        XCTAssertEqual(progressCount, 6)
        XCTAssertEqual(processingCount, 2)
        XCTAssertEqual(ignoredCount, 1)

        // First video-pass tick: 0%, unknown speed/eta.
        assertProgress(log[0], percent: 0.0, speed: nil, eta: nil)
        // Audio pass completes at 100%.
        assertProgress(log[5], percent: 1.0, speed: "1.30MiB/s", eta: "00:00")
    }
}
