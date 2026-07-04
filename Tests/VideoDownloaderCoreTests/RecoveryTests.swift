import XCTest
@testable import VideoDownloaderCore

final class PartialScannerTests: XCTestCase {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PartialScannerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touch(_ dir: URL, _ name: String, bytes: Int = 8) {
        try? Data(repeating: 0, count: bytes).write(to: dir.appendingPathComponent(name))
    }

    func test_scan_groupsMultiStreamPartialsByMediaID_ignoresCompletedFiles() {
        let dir = makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        // One best-quality download: separate video + audio streams, a .ytdl, and a fragment.
        touch(dir, "Clip One [abc123].f137.mp4.part")
        touch(dir, "Clip One [abc123].f251.webm.part")
        touch(dir, "Clip One [abc123].mp4.ytdl")
        touch(dir, "Clip One [abc123].f137.mp4.part-Frag3.part")
        // A second, single-file download.
        touch(dir, "Other [zzz].mp4.part")
        // A completed file — no partial suffix, must be ignored.
        touch(dir, "Done [k].mp4")

        let partials = PartialScanner.scan(directory: dir)
        XCTAssertEqual(partials.count, 2)
        let byID = Dictionary(uniqueKeysWithValues: partials.compactMap { p in p.mediaID.map { ($0, p) } })
        XCTAssertEqual(byID["abc123"]?.files.count, 4)
        XCTAssertEqual(byID["zzz"]?.files.count, 1)
        XCTAssertGreaterThan(byID["abc123"]?.totalSize ?? 0, 0)
    }

    func test_lastBracketID_takesTheIdBeforeExtension() {
        XCTAssertEqual(PartialScanner.lastBracketID("A [b] title [xy_9-Z].mp4.part"), "xy_9-Z")
        XCTAssertEqual(PartialScanner.lastBracketID("Song [aqz-KE-bpKQ].m4a.part"), "aqz-KE-bpKQ")
        XCTAssertNil(PartialScanner.lastBracketID("no brackets here.mp4.part"))
    }

    func test_delete_removesFilesAndReportsCount() {
        let dir = makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        touch(dir, "x [id].mp4.part"); touch(dir, "x [id].mp4.ytdl")
        let partials = PartialScanner.scan(directory: dir)
        XCTAssertEqual(PartialScanner.delete(partials.flatMap(\.files)), 2)
        XCTAssertTrue(PartialScanner.scan(directory: dir).isEmpty)
    }

    func test_scan_missingDirectory_isEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(PartialScanner.scan(directory: missing).isEmpty)
    }
}

final class QueueSnapshotItemTests: XCTestCase {

    func test_snapshot_roundTrips_andNormalizesInFlightStateToReady() throws {
        let item = DownloadItem(url: "https://x/1", title: "One", source: "Youtube",
                                mediaID: "abc", selectedFormat: .audio(.best), state: .downloading)
        let snap = QueueSnapshotItem(item: item)
        XCTAssertEqual(snap.mediaID, "abc")
        XCTAssertEqual(snap.state, .downloading)          // saved as-is

        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(QueueSnapshotItem.self, from: data)
        XCTAssertEqual(decoded, snap)

        // A download that was in flight at quit comes back resumable, not stuck.
        let restored = decoded.toItem()
        XCTAssertEqual(restored.state, .ready)
        XCTAssertEqual(restored.selectedFormat, .audio(.best))
        XCTAssertEqual(restored.mediaID, "abc")
        XCTAssertEqual(restored.url, "https://x/1")
    }

    func test_snapshot_keepsTerminalStatesAndOutputPath() {
        let out = URL(fileURLWithPath: "/tmp/One [abc].mp4")
        let item = DownloadItem(url: "https://x/1", mediaID: "abc",
                                state: .completed, outputPath: out)
        let restored = QueueSnapshotItem(item: item).toItem()
        XCTAssertEqual(restored.state, .completed)
        XCTAssertEqual(restored.outputPath, out)
    }
}

@MainActor
final class QueuePersistenceTests: XCTestCase {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("queue-\(UUID().uuidString).json")
    }

    private func makeSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "QueuePersistenceTests-\(UUID().uuidString)")!)
    }

    private func makeStore(_ url: URL) -> QueueStore {
        QueueStore(prober: FakeProber(), engine: FakeEngine(),
                   binaries: FakeBinaries(), settings: makeSettings(), persistenceURL: url)
    }

    /// Pre-write a queue.json and confirm a fresh store restores it, normalizing
    /// in-flight states to `.ready` while keeping terminal ones.
    func test_restore_loadsSnapshot_normalizingInFlightStates() throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = [
            QueueSnapshotItem(item: DownloadItem(url: "https://x/1", mediaID: "a", state: .downloading)),
            QueueSnapshotItem(item: DownloadItem(url: "https://x/2", mediaID: "b", state: .completed)),
            QueueSnapshotItem(item: DownloadItem(url: "https://x/3", mediaID: "c", state: .queued)),
        ]
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(snapshot).write(to: url)

        let store = makeStore(url)
        XCTAssertEqual(store.items.map(\.state), [.ready, .completed, .ready])
        XCTAssertEqual(store.items.map(\.mediaID), ["a", "b", "c"])
        XCTAssertTrue(store.hasFinishedItems)   // the completed one
    }

    /// saveNow writes a file a second store can restore (exercises the write path).
    func test_saveNow_thenReload_roundTripsThroughDisk() async throws {
        let url = tempFile(); defer { try? FileManager.default.removeItem(at: url) }

        let prober = FakeProber()
        prober.itemsToReturn = [DownloadItem(url: "https://x/1", mediaID: "a", state: .ready)]
        let store = QueueStore(prober: prober, engine: FakeEngine(),
                               binaries: FakeBinaries(), settings: makeSettings(),
                               persistenceURL: url)
        await store.add(url: "https://x/1")
        store.saveNow()

        // The write is offloaded to a utility queue — poll until it lands.
        let deadline = Date().addingTimeInterval(2)
        while !FileManager.default.fileExists(atPath: url.path), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let reloaded = makeStore(url)
        XCTAssertEqual(reloaded.items.map(\.url), ["https://x/1"])
        XCTAssertEqual(reloaded.items.map(\.mediaID), ["a"])
    }

    func test_emptyOrMissingFile_restoresEmptyQueue() {
        let store = makeStore(tempFile())   // file doesn't exist yet
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(store.hasFinishedItems)
    }
}
