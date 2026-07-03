import XCTest
@testable import VideoDownloaderCore

final class HistoryFilterTests: XCTestCase {

    private func entry(
        url: String = "https://example.com/v",
        title: String? = nil,
        source: String? = nil,
        addedAt: Date = Date(timeIntervalSince1970: 0),
        completedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> HistoryEntry {
        HistoryEntry(url: url, title: title, source: source,
                     formatSummary: "Video · Migliore",
                     addedAt: addedAt, completedAt: completedAt)
    }

    private let day: TimeInterval = 86_400

    func test_noFilters_returnsAll() {
        let entries = [entry(url: "a"), entry(url: "b")]
        XCTAssertEqual(HistoryFilter.filter(entries).count, 2)
    }

    func test_sourceFilter_matchesExactly() {
        let entries = [
            entry(url: "a", source: "Youtube"),
            entry(url: "b", source: "Vimeo"),
            entry(url: "c", source: nil),
        ]
        let result = HistoryFilter.filter(entries, source: "Youtube")
        XCTAssertEqual(result.map(\.url), ["a"])
    }

    func test_query_searchesTitleAndURL_caseInsensitive() {
        let entries = [
            entry(url: "https://x.com/rick", title: "Never Gonna Give You Up"),
            entry(url: "https://x.com/other", title: "Something Else"),
        ]
        XCTAssertEqual(HistoryFilter.filter(entries, query: "never").map(\.title),
                       ["Never Gonna Give You Up"])
        // Matches the URL too.
        XCTAssertEqual(HistoryFilter.filter(entries, query: "RICK").count, 1)
        // Blank query is a no-op.
        XCTAssertEqual(HistoryFilter.filter(entries, query: "   ").count, 2)
    }

    func test_downloadedRange_inclusiveBounds() {
        let e1 = entry(url: "1", completedAt: Date(timeIntervalSince1970: 0))
        let e2 = entry(url: "2", completedAt: Date(timeIntervalSince1970: day))
        let e3 = entry(url: "3", completedAt: Date(timeIntervalSince1970: 2 * day))
        let entries = [e1, e2, e3]

        // from == e2's exact date ⇒ inclusive lower bound keeps e2 and e3.
        XCTAssertEqual(
            HistoryFilter.filter(entries, downloadedFrom: Date(timeIntervalSince1970: day)).map(\.url),
            ["2", "3"])
        // to == e2's exact date ⇒ inclusive upper bound keeps e1 and e2.
        XCTAssertEqual(
            HistoryFilter.filter(entries, downloadedTo: Date(timeIntervalSince1970: day)).map(\.url),
            ["1", "2"])
        // Both bounds narrow to just e2.
        XCTAssertEqual(
            HistoryFilter.filter(entries,
                                 downloadedFrom: Date(timeIntervalSince1970: day),
                                 downloadedTo: Date(timeIntervalSince1970: day)).map(\.url),
            ["2"])
    }

    func test_addedRange_inclusiveBounds() {
        let e1 = entry(url: "1", addedAt: Date(timeIntervalSince1970: 0))
        let e2 = entry(url: "2", addedAt: Date(timeIntervalSince1970: day))
        let entries = [e1, e2]

        XCTAssertEqual(
            HistoryFilter.filter(entries, addedFrom: Date(timeIntervalSince1970: day)).map(\.url),
            ["2"])
        XCTAssertEqual(
            HistoryFilter.filter(entries, addedTo: Date(timeIntervalSince1970: 0)).map(\.url),
            ["1"])
    }

    func test_nilBounds_areUnbounded() {
        let entries = [
            entry(url: "1", completedAt: Date(timeIntervalSince1970: -day)),
            entry(url: "2", completedAt: Date(timeIntervalSince1970: 10 * day)),
        ]
        // All nil bounds ⇒ nothing excluded by date.
        XCTAssertEqual(HistoryFilter.filter(entries).count, 2)
    }

    func test_combinedFilters_applyTogether() {
        let entries = [
            entry(url: "https://x.com/keep", title: "Keep", source: "Youtube",
                  completedAt: Date(timeIntervalSince1970: day)),
            entry(url: "https://x.com/wrongSource", title: "Keep", source: "Vimeo",
                  completedAt: Date(timeIntervalSince1970: day)),
            entry(url: "https://x.com/wrongDate", title: "Keep", source: "Youtube",
                  completedAt: Date(timeIntervalSince1970: 100 * day)),
        ]
        let result = HistoryFilter.filter(
            entries,
            source: "Youtube",
            query: "keep",
            downloadedFrom: Date(timeIntervalSince1970: 0),
            downloadedTo: Date(timeIntervalSince1970: 2 * day))
        XCTAssertEqual(result.map(\.url), ["https://x.com/keep"])
    }
}
