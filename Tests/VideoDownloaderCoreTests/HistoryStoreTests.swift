import XCTest
@testable import VideoDownloaderCore

@MainActor
final class HistoryStoreTests: XCTestCase {

    /// A throwaway temp file so tests never touch the real history on disk.
    private func ephemeralFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString).json")
    }

    private func removeFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Poll until `condition` holds or the timeout elapses (the store writes to
    /// disk off the main thread, so persistence isn't observable synchronously).
    private func waitUntil(timeout: TimeInterval = 2.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000) // 5 ms
        }
    }

    private func completedItem(url: String, title: String? = nil, addedAt: Date = Date()) -> DownloadItem {
        DownloadItem(url: url, title: title, state: .completed, addedAt: addedAt)
    }

    // MARK: - record / ordering

    func test_record_prependsNewestFirst() {
        let url = ephemeralFileURL(); defer { removeFile(url) }
        let store = HistoryStore(fileURL: url)

        store.record(completedItem(url: "https://example.com/1"))
        store.record(completedItem(url: "https://example.com/2"))

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.map(\.url),
                       ["https://example.com/2", "https://example.com/1"])
    }

    func test_record_capturesItemFields() {
        let url = ephemeralFileURL(); defer { removeFile(url) }
        let store = HistoryStore(fileURL: url)
        let added = Date(timeIntervalSince1970: 1_000_000)
        var item = DownloadItem(url: "https://youtube.com/watch?v=x",
                                title: "Clip", source: "Youtube",
                                selectedFormat: .audio(.best),
                                state: .completed, addedAt: added)
        item.outputPath = URL(fileURLWithPath: "/tmp/clip.mp3")

        let completed = Date(timeIntervalSince1970: 1_000_500)
        store.record(item, completedAt: completed)

        let entry = try! XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.title, "Clip")
        XCTAssertEqual(entry.source, "Youtube")
        XCTAssertEqual(entry.formatSummary, "Audio MP3")
        XCTAssertEqual(entry.outputPath, "/tmp/clip.mp3")
        XCTAssertEqual(entry.addedAt, added)
        XCTAssertEqual(entry.completedAt, completed)
        XCTAssertEqual(entry.host, "youtube.com")
    }

    // MARK: - persistence

    func test_persistsAcrossInstances() async {
        let url = ephemeralFileURL(); defer { removeFile(url) }
        let first = HistoryStore(fileURL: url)
        first.record(completedItem(url: "https://example.com/a", title: "A"))
        first.record(completedItem(url: "https://example.com/b", title: "B"))

        // The write is detached; wait for the file to appear before reloading.
        await waitUntil { FileManager.default.fileExists(atPath: url.path) }

        var second = HistoryStore(fileURL: url)
        await waitUntil { second.entries.count == 2 }
        if second.entries.count != 2 { second = HistoryStore(fileURL: url) }

        XCTAssertEqual(second.entries.count, 2)
        XCTAssertEqual(second.entries.map(\.title), ["B", "A"])
    }

    func test_load_missingFile_isEmpty() {
        let url = ephemeralFileURL(); defer { removeFile(url) }
        let store = HistoryStore(fileURL: url)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func test_load_corruptFile_isEmpty() {
        let url = ephemeralFileURL(); defer { removeFile(url) }
        try! Data("{ not valid json".utf8).write(to: url)
        let store = HistoryStore(fileURL: url)
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - remove / clear

    func test_remove_dropsById() {
        let url = ephemeralFileURL(); defer { removeFile(url) }
        let store = HistoryStore(fileURL: url)
        store.record(completedItem(url: "https://example.com/1"))
        store.record(completedItem(url: "https://example.com/2"))
        let targetID = try! XCTUnwrap(store.entries.first).id

        store.remove(targetID)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.url, "https://example.com/1")
    }

    func test_clear_removesEverything() {
        let url = ephemeralFileURL(); defer { removeFile(url) }
        let store = HistoryStore(fileURL: url)
        store.record(completedItem(url: "https://example.com/1"))
        store.record(completedItem(url: "https://example.com/2"))

        store.clear()

        XCTAssertTrue(store.entries.isEmpty)
    }
}
