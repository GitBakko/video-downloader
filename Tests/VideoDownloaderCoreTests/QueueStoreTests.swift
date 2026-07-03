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

    func test_add_showsProbingPlaceholder_thenReplacesWithReadyItems() async {
        let (sut, prober, _) = makeSUT()
        prober.itemsToReturn = makeReadyItems(2)
        let gate = ProbeGate()
        prober.gate = gate

        let task = Task { await sut.add(url: "https://example.com/playlist") }

        // The placeholder appears immediately, before the (gated) probe returns.
        await waitUntil { sut.items.count == 1 && sut.items.first?.state == .probing }
        XCTAssertEqual(sut.items.count, 1)
        XCTAssertEqual(sut.items.first?.state, .probing)
        XCTAssertEqual(sut.items.first?.url, "https://example.com/playlist")

        await gate.open()
        await task.value

        XCTAssertEqual(sut.items.count, 2)
        XCTAssertTrue(sut.items.allSatisfy { $0.state == .ready })
    }

    func test_add_probeFailure_marksPlaceholderFailedWithMessage() async {
        let (sut, prober, _) = makeSUT()
        prober.errorToThrow = MediaProbeError.ytDlpFailed(exitCode: 1, message: "ERROR: Video unavailable")

        await sut.add(url: "https://example.com/bad")

        XCTAssertEqual(sut.items.count, 1)
        XCTAssertEqual(sut.items[0].state, .failed)
        XCTAssertEqual(sut.items[0].url, "https://example.com/bad")
        XCTAssertEqual(sut.items[0].errorMessage, "ERROR: Video unavailable")
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

    func test_startAll_promotesExactlyTwoAndQueuesTheRest() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(3)
        await sut.add(url: "https://example.com/playlist")

        sut.startAll()

        XCTAssertEqual(sut.items.filter { $0.state == .downloading }.count, 2)
        XCTAssertEqual(sut.items.filter { $0.state == .queued }.count, 1)
        XCTAssertEqual(engine.startedIDs.count, 2, "only the two promoted items are handed to the engine")
    }

    func test_startDownload_promotesSingleReadyItem() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(1)
        await sut.add(url: "https://example.com/v")
        let id = sut.items[0].id

        sut.startDownload(id)

        XCTAssertEqual(sut.items[0].state, .downloading)
        XCTAssertEqual(engine.startedIDs, [id])
    }

    func test_finishingADownload_promotesNextQueued() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(3)
        await sut.add(url: "https://example.com/playlist")
        sut.startAll()

        let first = sut.items[0].id
        let third = sut.items[2].id
        XCTAssertEqual(sut.items[2].state, .queued)

        engine.finish(first, outputPath: URL(fileURLWithPath: "/tmp/out.mp4"))

        await waitUntil { sut.items.first(where: { $0.id == third })?.state == .downloading }

        XCTAssertEqual(sut.items.first(where: { $0.id == first })?.state, .completed)
        XCTAssertEqual(sut.items.first(where: { $0.id == first })?.outputPath,
                       URL(fileURLWithPath: "/tmp/out.mp4"))
        XCTAssertEqual(sut.items.first(where: { $0.id == third })?.state, .downloading)
        XCTAssertEqual(sut.items.filter { $0.state == .downloading }.count, 2)
    }

    func test_pause_preventsPromotionOnStartAll() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(3)
        await sut.add(url: "https://example.com/playlist")

        sut.togglePauseQueue()          // paused
        sut.startAll()

        XCTAssertEqual(sut.items.filter { $0.state == .downloading }.count, 0)
        XCTAssertEqual(sut.items.filter { $0.state == .queued }.count, 3)
        XCTAssertTrue(engine.startedIDs.isEmpty)

        sut.togglePauseQueue()          // resumed
        XCTAssertEqual(sut.items.filter { $0.state == .downloading }.count, 2)
        XCTAssertEqual(sut.items.filter { $0.state == .queued }.count, 1)
    }

    func test_pauseWhileDownloading_blocksPromotionUntilResume() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(3)
        await sut.add(url: "https://example.com/playlist")
        sut.startAll()                  // 2 downloading, 1 queued

        let first = sut.items[0].id
        let third = sut.items[2].id

        sut.togglePauseQueue()          // pause: in-flight downloads untouched
        engine.finish(first)            // a slot frees, but we are paused

        // Give the completion a chance to run; the third must NOT promote.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(sut.items.first(where: { $0.id == first })?.state, .completed)
        XCTAssertEqual(sut.items.first(where: { $0.id == third })?.state, .queued)

        sut.togglePauseQueue()          // resume → now it promotes
        await waitUntil { sut.items.first(where: { $0.id == third })?.state == .downloading }
        XCTAssertEqual(sut.items.first(where: { $0.id == third })?.state, .downloading)
        _ = engine
    }

    func test_cancelQueued_marksCancelledWithoutStarting() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(3)
        await sut.add(url: "https://example.com/playlist")
        sut.startAll()                  // items[2] is queued

        let queuedID = sut.items[2].id
        sut.cancel(queuedID)

        XCTAssertEqual(sut.items.first(where: { $0.id == queuedID })?.state, .cancelled)
        XCTAssertFalse(engine.startedIDs.contains(queuedID),
                       "a queued item that is cancelled is never handed to the engine")
    }

    func test_cancelDownloading_terminatesMarksCancelledAndPromotesNext() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(3)
        await sut.add(url: "https://example.com/playlist")
        sut.startAll()                  // items[0],[1] downloading; items[2] queued

        let first = sut.items[0].id
        let third = sut.items[2].id

        sut.cancel(first)

        XCTAssertTrue(engine.cancelledIDs.contains(first))
        await waitUntil { sut.items.first(where: { $0.id == first })?.state == .cancelled }
        await waitUntil { sut.items.first(where: { $0.id == third })?.state == .downloading }

        XCTAssertEqual(sut.items.first(where: { $0.id == first })?.state, .cancelled)
        XCTAssertEqual(sut.items.first(where: { $0.id == third })?.state, .downloading)
    }

    func test_retry_resetsFailedItemToReadyAndRestarts() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(1)
        await sut.add(url: "https://example.com/v")
        let id = sut.items[0].id
        sut.startDownload(id)
        engine.fail(id, DownloadError.failed(message: "boom", exitCode: 1))
        await waitUntil { sut.items[0].state == .failed }
        XCTAssertNotNil(sut.items[0].errorMessage)

        sut.retry(id)

        await waitUntil { sut.items[0].state == .downloading }
        XCTAssertEqual(sut.items[0].state, .downloading)
        XCTAssertNil(sut.items[0].errorMessage)
        XCTAssertEqual(engine.startedIDs.filter { $0 == id }.count, 2,
                       "retry hands the item to the engine a second time")
    }

    func test_progressThenProcessing_updatesRowThenGoesIndeterminate() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(1)
        await sut.add(url: "https://example.com/v")
        let id = sut.items[0].id
        sut.startDownload(id)
        XCTAssertEqual(sut.items[0].state, .downloading)

        engine.emitProgress(id, percent: 0.5, speed: "4.2 MB/s", eta: "0:38", stage: nil)
        await waitUntil { sut.items[0].progress == 0.5 }
        XCTAssertEqual(sut.items[0].state, .downloading)
        XCTAssertEqual(sut.items[0].speed, "4.2 MB/s")
        XCTAssertEqual(sut.items[0].eta, "0:38")
        // No pass label is asserted: the real pipeline produces stage == nil and the
        // UI derives the "Scaricamento…" caption from `state`, not from `stage`.

        engine.emitProcessing(id)
        await waitUntil { sut.items[0].state == .processing }
        XCTAssertEqual(sut.items[0].state, .processing)
        XCTAssertNil(sut.items[0].progress, "post-processing is indeterminate")
    }

    // MARK: - M1: cancelling a probing item

    func test_cancelProbing_cancelsProbeAndMarksCancelled() async {
        let (sut, prober, _) = makeSUT()
        prober.itemsToReturn = makeReadyItems(2)
        let gate = ProbeGate()
        prober.gate = gate

        let task = Task { await sut.add(url: "https://example.com/playlist") }
        // Wait for the placeholder to appear while the probe is gated (in-flight).
        await waitUntil { sut.items.count == 1 && sut.items.first?.state == .probing }
        let id = sut.items[0].id

        sut.cancel(id)
        XCTAssertEqual(sut.items.first(where: { $0.id == id })?.state, .cancelled,
                       "cancelling a probing item marks it cancelled immediately")

        // Let the (now-cancelled) probe unwind; its result must be discarded.
        await gate.open()
        await task.value

        XCTAssertEqual(sut.items.count, 1, "the discarded probe result is NOT appended")
        XCTAssertEqual(sut.items[0].state, .cancelled,
                       "a cancelled probe stays cancelled even though it returned items")
    }

    // MARK: - S14: empty playlist feedback

    func test_add_emptyPlaylist_marksPlaceholderFailedWithMessage() async {
        let (sut, prober, _) = makeSUT()
        prober.itemsToReturn = []   // playlist with no downloadable entries

        await sut.add(url: "https://example.com/emptyplaylist")

        XCTAssertEqual(sut.items.count, 1, "the placeholder is kept, not silently removed")
        XCTAssertEqual(sut.items[0].state, .failed)
        XCTAssertEqual(sut.items[0].errorMessage, "La playlist non contiene video disponibili.")
    }

    // MARK: - S17: re-adding a playlist doesn't duplicate its videos

    func test_add_reAddingSamePlaylist_doesNotDuplicateItems() async {
        let (sut, prober, _) = makeSUT()
        prober.itemsToReturn = makeReadyItems(2)

        await sut.add(url: "https://example.com/playlist")
        XCTAssertEqual(sut.items.count, 2)

        // Re-adding the same playlist URL re-probes and returns the same videos;
        // they must be deduped by URL rather than appended again (S17).
        await sut.add(url: "https://example.com/playlist")

        XCTAssertEqual(sut.items.count, 2, "already-queued videos are not duplicated")
        XCTAssertEqual(Set(sut.items.map { $0.url }).count, 2)
    }

    func test_add_reAddingPlaylistWithNewItem_appendsOnlyTheNewOne() async {
        let (sut, prober, _) = makeSUT()
        prober.itemsToReturn = makeReadyItems(2)   // video/0, video/1
        await sut.add(url: "https://example.com/playlist")
        XCTAssertEqual(sut.items.count, 2)

        prober.itemsToReturn = makeReadyItems(3)   // video/0, video/1, video/2
        await sut.add(url: "https://example.com/playlist")

        XCTAssertEqual(sut.items.count, 3, "only the genuinely-new video is appended")
        XCTAssertEqual(sut.items.map { $0.url },
                       ["https://example.com/video/0",
                        "https://example.com/video/1",
                        "https://example.com/video/2"])
    }

    // MARK: - S12/P15: indexByID stays correct across placeholder replacement

    func test_progress_updatesTheRightItem_afterPlaceholderExpandedToPlaylist() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(3)
        await sut.add(url: "https://example.com/playlist")

        // The middle item's index only becomes valid after replaceSubrange +
        // index rebuild; drive a progress event straight at it.
        let midID = sut.items[1].id
        sut.startDownload(midID)
        engine.emitProgress(midID, percent: 0.7, speed: "1 MB/s", eta: "0:10")
        await waitUntil { sut.items[1].progress == 0.7 }

        XCTAssertEqual(sut.items[1].progress, 0.7)
        XCTAssertNil(sut.items[0].progress, "neighbouring rows are untouched")
        XCTAssertNil(sut.items[2].progress)
    }

    // MARK: - S16: cancel everything on quit

    func test_cancelAll_terminatesEngineAndCancelsRunningDownloads() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(2)
        await sut.add(url: "https://example.com/playlist")
        sut.startAll()   // both items downloading

        sut.cancelAll()

        XCTAssertEqual(engine.terminateAllCount, 1, "the engine is told to terminate all processes")
        await waitUntil { sut.items.allSatisfy { $0.state == .cancelled } }
        XCTAssertTrue(sut.items.allSatisfy { $0.state == .cancelled },
                      "terminated downloads settle as cancelled")
    }

    // MARK: - Queue management: remove / removeCompleted / clearAll

    func test_remove_dropsSingleItem_andKeepsIndexConsistent() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(3)
        await sut.add(url: "https://example.com/playlist")
        XCTAssertEqual(sut.items.count, 3)

        let victim = sut.items[1].id
        let survivor = sut.items[2].id
        sut.remove(victim)

        XCTAssertEqual(sut.items.count, 2)
        XCTAssertFalse(sut.items.contains { $0.id == victim })
        // The index is rebuilt after removal: driving the survivor still hits it.
        sut.startDownload(survivor)
        engine.emitProgress(survivor, percent: 0.5)
        await waitUntil { sut.items.first(where: { $0.id == survivor })?.progress == 0.5 }
        XCTAssertEqual(sut.items.first(where: { $0.id == survivor })?.progress, 0.5)
    }

    func test_removeCompleted_dropsCompletedKeepsTheRest() async {
        let (sut, prober, engine) = makeSUT()
        prober.itemsToReturn = makeReadyItems(2)
        await sut.add(url: "https://example.com/playlist")
        sut.startAll()                       // both downloading
        let first = sut.items[0].id
        engine.finish(first)                 // first → completed
        await waitUntil { sut.items.first(where: { $0.id == first })?.state == .completed }

        sut.removeCompleted()

        XCTAssertEqual(sut.items.count, 1, "only the completed item is removed")
        XCTAssertFalse(sut.items.contains { $0.id == first })
    }

    func test_clearAll_emptiesTheQueue() async {
        let (sut, prober, _) = makeSUT()
        prober.itemsToReturn = makeReadyItems(3)
        await sut.add(url: "https://example.com/playlist")
        sut.clearAll()
        XCTAssertTrue(sut.items.isEmpty)
    }

    func test_setFormat_allowedWhileReady_rejectedOnceDownloading() async {
        let (sut, prober, _) = makeSUT()
        prober.itemsToReturn = makeReadyItems(1)
        await sut.add(url: "https://example.com/v")
        let id = sut.items[0].id

        // Allowed while ready.
        sut.setFormat(.audio(.best), for: id)
        XCTAssertEqual(sut.items[0].selectedFormat, .audio(.best))

        // Promote to downloading, then attempt an override.
        sut.startDownload(id)
        XCTAssertEqual(sut.items[0].state, .downloading)

        sut.setFormat(.video(.p720), for: id)
        XCTAssertEqual(sut.items[0].selectedFormat, .audio(.best),
                       "format override is rejected once the item has started")
    }
}
