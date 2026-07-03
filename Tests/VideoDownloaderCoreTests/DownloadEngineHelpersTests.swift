import XCTest
@testable import VideoDownloaderCore

final class DownloadEngineHelpersTests: XCTestCase {

    func test_destination_parsesDownloadDestinationLine() {
        let url = DownloadEngine.destination(from: "[download] Destination: /Users/x/Movies/Song.mp4")
        XCTAssertEqual(url, URL(fileURLWithPath: "/Users/x/Movies/Song.mp4"))
    }

    func test_destination_parsesExtractAudioDestinationLine() {
        let url = DownloadEngine.destination(from: "[ExtractAudio] Destination: /Users/x/Movies/Song.mp3")
        XCTAssertEqual(url, URL(fileURLWithPath: "/Users/x/Movies/Song.mp3"))
    }

    func test_destination_parsesMergerLine() {
        let url = DownloadEngine.destination(from: #"[Merger] Merging formats into "/Users/x/Movies/Clip.mkv""#)
        XCTAssertEqual(url, URL(fileURLWithPath: "/Users/x/Movies/Clip.mkv"))
    }

    func test_destination_parsesAlreadyDownloadedLine() {
        let url = DownloadEngine.destination(from: "[download] /Users/x/Movies/Clip.mp4 has already been downloaded")
        XCTAssertEqual(url, URL(fileURLWithPath: "/Users/x/Movies/Clip.mp4"))
    }

    func test_destination_returnsNilForProgressLine() {
        XCTAssertNil(DownloadEngine.destination(from: " 42.0%|4.20MiB/s|00:12"))
    }

    func test_lastMeaningfulLine_prefersErrorLine() {
        let stderr = """
        WARNING: something minor
        [debug] blah
        ERROR: Video unavailable
        """
        XCTAssertEqual(DownloadEngine.lastMeaningfulLine(stderr), "ERROR: Video unavailable")
    }

    func test_lastMeaningfulLine_fallsBackToLastNonEmptyLine() {
        let stderr = "line one\n   \nlast line\n"
        XCTAssertEqual(DownloadEngine.lastMeaningfulLine(stderr), "last line")
    }

    func test_lastMeaningfulLine_emptyForBlankInput() {
        XCTAssertEqual(DownloadEngine.lastMeaningfulLine("   \n\n"), "")
    }

    func test_downloadError_userMessage_usesMessage() {
        let error = DownloadError.failed(message: "ERROR: nope", exitCode: 1)
        XCTAssertEqual(error.userMessage, "ERROR: nope")
    }

    func test_downloadError_userMessage_fallbackWhenEmpty() {
        let error = DownloadError.failed(message: "", exitCode: 1)
        XCTAssertEqual(error.userMessage, "Download non riuscito.")
    }

    // MARK: - P17: output directory fallback

    func test_outputDirectory_extractsDestinationFromArguments() {
        let args = ["-f", "bv*+ba/b", "-o", "/Users/x/Movies/%(title)s [%(id)s].%(ext)s", "--newline"]
        XCTAssertEqual(DownloadEngine.outputDirectory(from: args),
                       URL(fileURLWithPath: "/Users/x/Movies", isDirectory: true))
    }

    func test_outputDirectory_nilWhenNoOutputFlag() {
        XCTAssertNil(DownloadEngine.outputDirectory(from: ["-f", "best", "--newline"]))
    }
}
