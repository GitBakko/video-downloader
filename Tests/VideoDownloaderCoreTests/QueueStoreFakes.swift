import Foundation
@testable import VideoDownloaderCore

/// Fake prober: returns a configurable list (or throws) and records calls.
final class FakeProber: MediaProbing, @unchecked Sendable {
    var itemsToReturn: [DownloadItem] = []
    var errorToThrow: Error?
    private(set) var probedURLs: [String] = []
    /// Optional gate: when set, `probe` suspends until the test releases it,
    /// letting the test observe the intermediate `.probing` placeholder.
    var gate: ProbeGate?

    func probe(url: String) async throws -> [DownloadItem] {
        probedURLs.append(url)
        if let gate { await gate.wait() }
        if let error = errorToThrow { throw error }
        return itemsToReturn
    }
}

/// A one-shot async gate for tests: `probe` awaits `wait()`; the test calls `open()`.
actor ProbeGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

/// Fake engine: hands out one drivable AsyncThrowingStream per item id.
/// The build closure of AsyncThrowingStream runs SYNCHRONOUSLY, so the
/// continuation is registered before `events(for:)` returns — making the
/// queue-promotion assertions deterministic.
final class FakeEngine: Downloading, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncThrowingStream<DownloadEvent, Error>.Continuation] = [:]
    private(set) var startedIDs: [UUID] = []
    private(set) var cancelledIDs: [UUID] = []

    func events(for item: DownloadItem, arguments: [String]) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            startedIDs.append(item.id)
            continuations[item.id] = continuation
            lock.unlock()
        }
    }

    func cancel(_ id: UUID) {
        lock.lock()
        cancelledIDs.append(id)
        let continuation = continuations[id]
        lock.unlock()
        continuation?.finish(throwing: CancellationError())
    }

    // MARK: Test drivers
    func emitProgress(_ id: UUID, percent: Double?, speed: String? = nil, eta: String? = nil, stage: String? = nil) {
        continuation(for: id)?.yield(.progress(percent: percent, speed: speed, eta: eta, stage: stage))
    }
    func emitProcessing(_ id: UUID) {
        continuation(for: id)?.yield(.processing)
    }
    func finish(_ id: UUID, outputPath: URL? = nil) {
        let c = continuation(for: id)
        c?.yield(.finished(outputPath: outputPath))
        c?.finish()
    }
    func fail(_ id: UUID, _ error: Error) {
        continuation(for: id)?.finish(throwing: error)
    }

    private func continuation(for id: UUID) -> AsyncThrowingStream<DownloadEvent, Error>.Continuation? {
        lock.lock(); defer { lock.unlock() }
        return continuations[id]
    }
}

/// Fake binaries: harmless placeholder paths (never actually executed).
final class FakeBinaries: BinaryProviding, @unchecked Sendable {
    var ytDlpURL: URL = URL(fileURLWithPath: "/tmp/fake/yt-dlp")
    var ffmpegDirectory: URL = URL(fileURLWithPath: "/tmp/fake")
    var ytDlpVersion: String? = "2026.07.01"
    func ensureInstalled(onProgress: @escaping @Sendable (Double) -> Void) async throws { onProgress(1) }
    func updateYtDlp() async throws {}
}
