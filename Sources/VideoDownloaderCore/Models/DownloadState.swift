/// The lifecycle state of a single download item (spec §4).
public enum DownloadState: String, Equatable, Sendable, CaseIterable, Codable {
    case probing
    case ready
    case queued
    case downloading
    case processing
    case completed
    case failed
    case cancelled

    /// The state an item is restored to when the queue is reloaded at launch.
    /// Nothing can still be in flight after a relaunch, so any in-progress state
    /// drops to `.ready` — the download reappears resumable instead of stuck
    /// "Scaricamento". Terminal states (and plain `.ready`) are kept as-is.
    public var restoredAcrossLaunch: DownloadState {
        switch self {
        case .probing, .queued, .downloading, .processing: return .ready
        case .ready, .completed, .failed, .cancelled:       return self
        }
    }

    /// The user may change the selected format only before the download has
    /// actually started, i.e. while the item is `ready` or `queued`.
    public var allowsFormatEditing: Bool {
        switch self {
        case .ready, .queued:
            return true
        case .probing, .downloading, .processing, .completed, .failed, .cancelled:
            return false
        }
    }

    /// A terminal state no longer changes on its own.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .probing, .ready, .queued, .downloading, .processing:
            return false
        }
    }
}
