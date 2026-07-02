import Foundation
import Observation

/// Persistent, user-facing settings (spec §3.5). Backed by `UserDefaults`,
/// `@Observable` so SwiftUI re-renders on change. Single source of truth for the
/// download destination, the default `FormatChoice`, and the embed toggle.
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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Keys.destination) {
            destination = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            destination = Self.defaultDestination
        }
        defaultFormat = Self.decode(defaults.string(forKey: Keys.defaultFormat)) ?? .video(.best)
        embedThumbnailAndMetadata = defaults.object(forKey: Keys.embed) as? Bool ?? false
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
