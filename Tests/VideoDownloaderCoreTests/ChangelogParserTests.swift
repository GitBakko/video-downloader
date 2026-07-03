import XCTest
@testable import VideoDownloaderCore

final class ChangelogParserTests: XCTestCase {

    private let sample = """
    # Changelog

    Some preamble that should be ignored.

    ## [Unreleased]

    _Nothing yet._

    ## [1.2.0] - 2026-07-03

    ### Added
    - **History** window with a long description that wraps onto
      a second line and must be joined into one bullet.
    - Configurable concurrency.

    ### Fixed
    - A crash on the stepper.

    ## [1.1.0] - 2026-07-01

    ### Changed
    - Faster extraction.

    <!-- a comment that must be ignored -->
    """

    func test_parsesVersionsDatesAndSections() {
        let releases = ChangelogParser.parse(sample)

        XCTAssertEqual(releases.map(\.version), ["Unreleased", "1.2.0", "1.1.0"])
        XCTAssertEqual(releases[1].date, "2026-07-03")
        XCTAssertNil(releases[0].date)

        // Unreleased has no bullets (only "_Nothing yet._") → no sections.
        XCTAssertTrue(releases[0].sections.isEmpty)

        let v120 = releases[1]
        XCTAssertEqual(v120.sections.map(\.heading), ["Added", "Fixed"])
        XCTAssertEqual(v120.sections[0].items.count, 2)
        // The wrapped bullet is joined into a single line.
        XCTAssertTrue(v120.sections[0].items[0].contains("wraps onto a second line"))
        XCTAssertEqual(v120.sections[1].items, ["A crash on the stepper."])

        XCTAssertEqual(releases[2].sections.first?.items, ["Faster extraction."])
    }

    func test_emptyOrHeaderOnly_yieldsNoReleases() {
        XCTAssertTrue(ChangelogParser.parse("").isEmpty)
        XCTAssertTrue(ChangelogParser.parse("# Changelog\n\njust preamble").isEmpty)
    }
}
