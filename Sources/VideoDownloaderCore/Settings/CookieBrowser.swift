import Foundation

/// The browsers the app offers for `--cookies-from-browser`.
///
/// Raw values are yt-dlp's own browser keywords and are what gets persisted and
/// passed on the command line, so they must not be renamed.
///
/// ponytail: only the browsers people actually run on macOS. yt-dlp also accepts
/// chromium/opera/vivaldi/whale — add them here if anyone asks.
public enum CookieBrowser: String, CaseIterable, Sendable {
    case safari
    case chrome
    case firefox
    case edge
    case brave

    public var displayName: String {
        switch self {
        case .safari:  return "Safari"
        case .chrome:  return "Google Chrome"
        case .firefox: return "Firefox"
        case .edge:    return "Microsoft Edge"
        case .brave:   return "Brave"
        }
    }

    /// Maps a persisted string back to a supported keyword, dropping anything
    /// unknown (an old or hand-edited default would otherwise make every yt-dlp
    /// call fail with "unsupported browser").
    public static func normalize(_ raw: String?) -> String? {
        guard let raw, let browser = CookieBrowser(rawValue: raw) else { return nil }
        return browser.rawValue
    }
}
