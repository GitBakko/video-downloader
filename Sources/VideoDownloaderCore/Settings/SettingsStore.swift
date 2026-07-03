import Foundation
import Observation

/// Persistent, user-facing settings (spec §3.5). Backed by `UserDefaults`,
/// `@Observable` so SwiftUI re-renders on change. Single source of truth for the
/// download destination, the default `FormatChoice`, and the embed toggle.
@MainActor
@Observable
public final class SettingsStore {

    @ObservationIgnored private let defaults: UserDefaults

    public var destination: URL {
        didSet { defaults.set(destination.path, forKey: Keys.destination) }
    }
    public var defaultFormat: FormatChoice {
        didSet { defaults.set(Self.encode(defaultFormat), forKey: Keys.defaultFormat) }
    }
    public var embedThumbnailAndMetadata: Bool {
        didSet { defaults.set(embedThumbnailAndMetadata, forKey: Keys.embed) }
    }
    /// When on, a newly-added link starts downloading immediately (no manual
    /// "Scarica"), whether it was typed/pasted or auto-detected from the clipboard.
    public var autoStartDownloads: Bool {
        didSet { defaults.set(autoStartDownloads, forKey: Keys.autoStart) }
    }
    /// Max downloads running at once across the whole app. Clamped to >= 1 at the
    /// read sites (never reassigned in `didSet` — that would recurse infinitely).
    public var maxConcurrentDownloads: Int {
        didSet { defaults.set(maxConcurrentDownloads, forKey: Keys.maxConcurrent) }
    }
    /// Max downloads running at once from a single source/site — keeps one site from
    /// hogging all slots (and helps avoid per-site rate-limiting). Clamped to >= 1.
    public var maxConcurrentPerSource: Int {
        didSet { defaults.set(maxConcurrentPerSource, forKey: Keys.maxPerSource) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Keys.destination) {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            destination = Self.defaultDestination
        }
        defaultFormat = Self.decode(defaults.string(forKey: Keys.defaultFormat)) ?? .video(.best)
        embedThumbnailAndMetadata = defaults.object(forKey: Keys.embed) as? Bool ?? false
        autoStartDownloads = defaults.object(forKey: Keys.autoStart) as? Bool ?? false
        maxConcurrentDownloads = max(1, defaults.object(forKey: Keys.maxConcurrent) as? Int ?? 2)
        maxConcurrentPerSource = max(1, defaults.object(forKey: Keys.maxPerSource) as? Int ?? 2)
    }

    /// The value consumed by Phase 6's `QueueStore` / `ArgumentBuilder` (Task 1b.3 type).
    public var downloadSettings: DownloadSettings {
        DownloadSettings(destination: destination,
                         embedThumbnailAndMetadata: embedThumbnailAndMetadata)
    }

    /// `~/Movies/VideoDownloader` (spec §3.5 default).
    public static var defaultDestination: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        return movies.appendingPathComponent("VideoDownloader", isDirectory: true)
    }

    private enum Keys {
        static let destination = "settings.destination"
        static let defaultFormat = "settings.defaultFormat"
        static let embed = "settings.embedThumbnailAndMetadata"
        static let autoStart = "settings.autoStartDownloads"
        static let maxConcurrent = "settings.maxConcurrentDownloads"
        static let maxPerSource = "settings.maxConcurrentPerSource"
    }

    // MARK: - FormatChoice <-> String (FormatChoice is not Codable)

    static func encode(_ choice: FormatChoice) -> String {
        switch choice {
        case .video(let q):     return "video:\(videoToken(q))"
        case .audio:            return "audio:best"
        case .specific(let id): return "specific:\(id)"
        }
    }

    static func decode(_ raw: String?) -> FormatChoice? {
        guard let raw, let sep = raw.firstIndex(of: ":") else { return nil }
        let kind = String(raw[..<sep])
        let value = String(raw[raw.index(after: sep)...])
        switch kind {
        case "video":    return .video(videoFromToken(value))
        case "audio":    return .audio(.best)
        case "specific": return value.isEmpty ? nil : .specific(formatID: value)
        default:         return nil
        }
    }

    private static func videoToken(_ q: VideoQuality) -> String {
        switch q {
        case .best:  return "best"
        case .p1080: return "1080"
        case .p720:  return "720"
        case .p480:  return "480"
        }
    }

    private static func videoFromToken(_ s: String) -> VideoQuality {
        switch s {
        case "1080": return .p1080
        case "720":  return .p720
        case "480":  return .p480
        default:     return .best
        }
    }
}
