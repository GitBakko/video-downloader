import XCTest
@testable import VideoDownloaderCore

@MainActor
final class QueueStoreTests: XCTestCase {

    /// Isolated UserDefaults suite so tests never read or write the real user prefs.
    private func makeEphemeralSettings() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "QueueStoreTests-\(UUID().uuidString)")!)
    }

    private func makeSUT() -> (QueueStore, FakeProber, FakeEngine) {
        let prober = FakeProber()
        let engine = FakeEngine()
        let sut = QueueStore(prober: prober, engine: engine,
                             binaries: FakeBinaries(), settings: makeEphemeralSettings())
        return (sut, prober, engine)
    }

    private func makeReadyItems(_ n: Int) -> [DownloadItem] {
        (0..<n).map { DownloadItem(url: "https://example.com/video/\($0)", state: .ready) }
    }

    /// Spins the main actor until `condition` holds or the timeout elapses.
    private func waitUntil(timeout: TimeInterval = 2.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000) // 2 ms
        }
    }

    func test_add_appendsReadyItems() async {
        let (sut, prober, _) = makeSUT()
        prober.itemsToReturn = makeReadyItems(2)

        await sut.add(url: "https://example.com/playlist")

        XCTAssertEqual(sut.items.count, 2)
        XCTAssertTrue(sut.items.allSatisfy { $0.state == .ready })
        XCTAssertEqual(prober.probedURLs, ["https://example.com/playlist"])
    }

    func test_add_appliesDefaultFormatFromSettings() async {
        let prober = FakeProber()
        let settings = makeEphemeralSettings()
        settings.defaultFormat = .audio(.best)
        let sut = QueueStore(prober: prober, engine: FakeEngine(),
                             binaries: FakeBinaries(), settings: settings)
        prober.itemsToReturn = makeReadyItems(2)

        await sut.add(url: "https://example.com/playlist")

        XCTAssertTrue(sut.items.allSatisfy { $0.selectedFormat == .audio(.best) },
                      "newly-added items inherit settings.defaultFormat")
    }
}
