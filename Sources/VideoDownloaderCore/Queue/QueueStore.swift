import Foundation
import Observation

@MainActor
@Observable
public final class QueueStore {

    public private(set) var items: [DownloadItem] = []
    public private(set) var isQueuePaused: Bool = false

    private let prober: MediaProbing
    private let engine: Downloading
    private let binaries: BinaryProviding
    private let settings: SettingsStore

    public init(prober: MediaProbing, engine: Downloading,
                binaries: BinaryProviding, settings: SettingsStore) {
        self.prober = prober
        self.engine = engine
        self.binaries = binaries
        self.settings = settings
    }

    // MARK: - Adding

    public func add(url: String) async {
        do {
            var probed = try await prober.probe(url: url)
            // Newly-added items inherit the user's default format (spec §5.2).
            for i in probed.indices { probed[i].selectedFormat = settings.defaultFormat }
            items.append(contentsOf: probed)
        } catch {
            // A probe failure never throws out of add; it surfaces as one
            // failed placeholder so the user sees why nothing was added.
            var failed = DownloadItem(url: url, state: .failed)
            failed.errorMessage = (error as? DownloadError)?.userMessage ?? error.localizedDescription
            items.append(failed)
        }
    }

    // MARK: - Starting

    private let maxConcurrent = 2
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    public func startDownload(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), item.state == .ready else { return }
        updateItem(id) { $0.state = .queued }
        promoteQueued()
    }

    public func startAll() {
        for item in items where item.state == .ready {
            updateItem(item.id) { $0.state = .queued }
        }
        promoteQueued()
    }

    public func togglePauseQueue() {
        isQueuePaused.toggle()
        if !isQueuePaused { promoteQueued() }
    }

    // MARK: - Promotion

    private var activeSlots: Int {
        items.filter { $0.state == .downloading || $0.state == .processing }.count
    }

    private func promoteQueued() {
        guard !isQueuePaused else { return }
        while activeSlots < maxConcurrent,
              let next = items.first(where: { $0.state == .queued }) {
            updateItem(next.id) { $0.state = .downloading }
            launch(next.id)
        }
    }

    private func launch(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let stream = engine.events(for: item, arguments: arguments(for: item))
        let task = Task { @MainActor in
            do {
                for try await event in stream {
                    self.handle(event, for: id)
                }
            } catch is CancellationError {
                self.updateItem(id) { $0.state = .cancelled }
            } catch {
                self.updateItem(id) {
                    $0.state = .failed
                    $0.errorMessage = (error as? DownloadError)?.userMessage ?? error.localizedDescription
                }
            }
            self.runningTasks[id] = nil
            self.promoteQueued()
        }
        runningTasks[id] = task
    }

    private func handle(_ event: DownloadEvent, for id: UUID) {
        switch event {
        case let .progress(percent, speed, eta, stage):
            updateItem(id) {
                guard $0.state == .downloading else { return } // ignore stray progress once processing
                $0.progress = percent
                $0.speed = speed
                $0.eta = eta
                $0.stage = stage
            }
        case .processing:
            updateItem(id) {
                $0.state = .processing
                $0.progress = nil   // indeterminate
                $0.speed = nil
                $0.eta = nil
                $0.stage = nil      // UI shows generic "Elaborazione…" from state
            }
        case let .finished(outputPath):
            updateItem(id) {
                $0.state = .completed
                $0.progress = 1.0
                $0.speed = nil
                $0.eta = nil
                $0.outputPath = outputPath
            }
        }
    }

    private func arguments(for item: DownloadItem) -> [String] {
        // The ONLY coupling to Phase 3's ArgumentBuilder. FakeEngine ignores
        // these in tests; adjust here if the real signature differs.
        ArgumentBuilder.downloadArguments(
            for: item.selectedFormat,
            item: item,
            settings: settings.downloadSettings,
            ffmpegDirectory: binaries.ffmpegDirectory)
    }

    // MARK: - Cancel

    public func cancel(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        switch item.state {
        case .ready, .queued:
            updateItem(id) { $0.state = .cancelled }
        case .downloading, .processing:
            engine.cancel(id) // stream ends throwing CancellationError → .cancelled, then a slot frees
        default:
            break
        }
    }

    // MARK: - Retry

    /// Reset a `.failed`/`.cancelled` item back to `.ready` — clearing its error
    /// and stale progress/stage — then re-enqueue it via `startDownload` (spec §7
    /// "Riprova"). A no-op for items in any other state.
    public func retry(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              item.state == .failed || item.state == .cancelled else { return }
        updateItem(id) {
            $0.state = .ready
            $0.errorMessage = nil
            $0.progress = nil
            $0.stage = nil
        }
        startDownload(id)
    }

    // MARK: - Format override

    public func setFormat(_ choice: FormatChoice, for id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              item.state == .ready || item.state == .queued else { return }
        updateItem(id) { $0.selectedFormat = choice }
    }

    // MARK: - Helpers

    private func updateItem(_ id: UUID, _ mutate: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }
}
