import Foundation

/// The lifecycle state of a single download item (spec §4).
public enum DownloadState: Equatable, Sendable, CaseIterable {
    case probing
    case ready
    case queued
    case downloading
    case processing
    case completed
    case failed
    case cancelled

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
}
