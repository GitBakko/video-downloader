import Foundation

/// Video quality presets (a separate axis from audio quality, spec §4).
public enum VideoQuality: Equatable, Sendable, CaseIterable {
    case best
    case p1080
    case p720
    case p480
}

/// Audio quality presets. v1 offers only `best` (extracted to MP3); the enum
/// stays extensible (e.g. 192/128 kbps) without touching call sites.
public enum AudioQuality: Equatable, Sendable, CaseIterable {
    case best
}

/// How the user wants an item downloaded: a video preset, an audio preset,
/// or a specific format id chosen from the full formats table (spec §4).
public enum FormatChoice: Equatable, Sendable {
    case video(VideoQuality)
    case audio(AudioQuality)
    case specific(formatID: String)

    /// True when the choice produces an audio-only (MP3) result.
    public var isAudioOnly: Bool {
        if case .audio = self { return true }
        return false
    }

    /// The explicit format id when the choice is `.specific`, otherwise nil.
    public var specificFormatID: String? {
        if case let .specific(formatID) = self { return formatID }
        return nil
    }
}
