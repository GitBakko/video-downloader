import Foundation
import Observation

@MainActor
@Observable
public final class QueueStore {

    public private(set) var items: [DownloadItem] = []
    public private(set) var isQueuePaused: Bool = false

    /// Invoked on the main actor each time an item reaches `.completed`. The app
    /// sets this to post the completion notification + sound, so items that
    /// finish while the window is closed are still announced (spec §5.2 / §9).
    public var onItemFinished: ((DownloadItem) -> Void)?

    private let prober: MediaProbing
    private let engine: Downloading
    private let binaries: BinaryProviding
    private let settings: SettingsStore

    /// O(1) id→index map, kept in sync with every structural mutation of `items`
    /// (append / replaceSubrange). Progress events fire ~10-20/s and each one
    /// calls `updateItem`, so an `items.firstIndex(where:)` there is an O(n) scan
    /// on a hot path — the map turns those lookups into O(1) (S12 / P15).
    private var indexByID: [UUID: Int] = [:]

    /// In-flight probe tasks keyed by the placeholder id, so a still-`.probing`
    /// item can be cancelled (M1). Cleared once the probe finishes.
    private var probingTasks: [UUID: Task<Void, Never>] = [:]

    public init(prober: MediaProbing, engine: Downloading,
                binaries: BinaryProviding, settings: SettingsStore) {
        self.prober = prober
        self.engine = engine
        self.binaries = binaries
        self.settings = settings
    }

    // MARK: - Adding

    public func add(url: String) async {
        // Show a `.probing` placeholder immediately so the row appears (with a
        // "Lettura formati…" spinner) and the list is never empty during a slow
        // yt-dlp probe (spec §3.2 / §4).
        let placeholder = DownloadItem(url: url, state: .probing)
        let placeholderID = placeholder.id
        appendItem(placeholder)

        // Run the probe inside a stored, cancellable Task so `cancel(_:)` can kill
        // an in-flight probe (M1). `add` still awaits the task, so callers that
        // rely on items being populated on return keep working.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performProbe(url: url, placeholderID: placeholderID)
        }
        probingTasks[placeholderID] = task
        await task.value
        probingTasks[placeholderID] = nil
    }

    private func performProbe(url: String, placeholderID: UUID) async {
        do {
            var probed = try await prober.probe(url: url)
            // If we were cancelled mid-probe, `cancel(_:)` already moved the item
            // to `.cancelled`; discard the result rather than overwrite it.
            if Task.isCancelled { return }
            // Newly-added items inherit the user's default format (spec §5.2).
            for i in probed.indices { probed[i].selectedFormat = settings.defaultFormat }
            if probed.isEmpty {
                // S14: an empty playlist becomes an explanatory failed row instead
                // of silently vanishing (which left the list empty with no reason).
                updateItem(placeholderID) {
                    $0.state = .failed
                    $0.errorMessage = "La playlist non contiene video disponibili."
                }
                return
            }
            // S17: re-adding a playlist URL re-probes the same videos; drop any
            // whose URL is already queued so they aren't duplicated. The placeholder
            // itself is excluded from the "already present" set — for a single video
            // its URL equals the probed item's, and matching it would wrongly drop it.
            let existingURLs = Set(items.lazy.filter { $0.id != placeholderID }.map(\.url))
            let deduped = probed.filter { !existingURLs.contains($0.url) }
            guard !deduped.isEmpty else {
                // Everything was already queued — remove the placeholder so a
                // re-add of an already-added playlist is a silent no-op.
                replaceItem(placeholderID, with: [])
                return
            }
            // Replace the placeholder with the (deduplicated) parsed `.ready` items.
            replaceItem(placeholderID, with: deduped)
        } catch {
            // A probe failure never throws out of add; the placeholder becomes a
            // failed row so the user sees why nothing was added. If the task was
            // cancelled, `cancel(_:)` already set `.cancelled` — don't clobber it
            // with the process's termination error.
            if Task.isCancelled { return }
            let message = (error as? DownloadError)?.userMessage ?? error.localizedDescription
            updateItem(placeholderID) {
                $0.state = .failed
                $0.errorMessage = message
            }
        }
    }

    // MARK: - Starting

    private let maxConcurrent = 2
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    public func startDownload(_ id: UUID) {
        guard let item = item(id), item.state == .ready else { return }
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
        // Compute the active count once and track promotions locally so the
        // O(n) `activeSlots` filter isn't recomputed on every loop iteration.
        var active = activeSlots
        while active < maxConcurrent,
              let next = items.first(where: { $0.state == .queued }) {
            updateItem(next.id) { $0.state = .downloading }
            launch(next.id)
            active += 1
        }
    }

    private func launch(_ id: UUID) {
        guard let item = item(id) else { return }
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
            // Fire the completion hook on the main actor so notifications are
            // posted even when the window is closed (spec §5.2 / §9).
            if let finished = item(id) {
                onItemFinished?(finished)
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
        guard let item = item(id) else { return }
        switch item.state {
        case .probing:
            // Kill the in-flight probe process (via the stored Task's cancellation
            // handler) and mark the row cancelled (M1).
            probingTasks[id]?.cancel()
            updateItem(id) { $0.state = .cancelled }
        case .ready, .queued:
            updateItem(id) { $0.state = .cancelled }
        case .downloading, .processing:
            engine.cancel(id) // stream ends throwing CancellationError → .cancelled, then a slot frees
        default:
            break
        }
    }

    /// Cancel every in-flight probe and terminate every running download so no
    /// orphaned yt-dlp process outlives the app. The app calls this on quit (S16).
    public func cancelAll() {
        for task in probingTasks.values { task.cancel() }
        engine.terminateAll()
    }

    // MARK: - Retry

    /// Reset a `.failed`/`.cancelled` item back to `.ready` — clearing its error
    /// and stale progress/stage — then re-enqueue it via `startDownload` (spec §7
    /// "Riprova"). A no-op for items in any other state.
    public func retry(_ id: UUID) {
        guard let item = item(id),
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
        guard let item = item(id),
              item.state == .ready || item.state == .queued else { return }
        updateItem(id) { $0.selectedFormat = choice }
    }

    // MARK: - Helpers

    /// O(1) lookup backed by `indexByID`.
    private func item(_ id: UUID) -> DownloadItem? {
        guard let index = indexByID[id], items.indices.contains(index) else { return nil }
        return items[index]
    }

    private func updateItem(_ id: UUID, _ mutate: (inout DownloadItem) -> Void) {
        guard let index = indexByID[id], items.indices.contains(index) else { return }
        mutate(&items[index])
    }

    // MARK: - `items` maintenance (keeps `indexByID` in sync)

    private func appendItem(_ item: DownloadItem) {
        indexByID[item.id] = items.count
        items.append(item)
    }

    private func appendItems(_ newItems: [DownloadItem]) {
        for item in newItems {
            indexByID[item.id] = items.count
            items.append(item)
        }
    }

    /// Replace the single item identified by `id` with `replacement`, keeping
    /// `indexByID` correct. `replaceSubrange` shifts the indices of everything
    /// after the edit, so the map is rebuilt (this happens once per add, off the
    /// hot path — correctness over cleverness).
    private func replaceItem(_ id: UUID, with replacement: [DownloadItem]) {
        guard let index = indexByID[id] else {
            appendItems(replacement)
            return
        }
        items.replaceSubrange(index...index, with: replacement)
        rebuildIndex()
    }

    private func rebuildIndex() {
        indexByID.removeAll(keepingCapacity: true)
        for (i, item) in items.enumerated() { indexByID[item.id] = i }
    }
}
