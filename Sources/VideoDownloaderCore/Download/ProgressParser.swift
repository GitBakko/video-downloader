import Foundation

/// Turns raw yt-dlp stdout lines into `DownloadEvent`s (spec §6 `--progress-template`).
/// yt-dlp strips the `download:` type prefix, so lines arrive as the bare
/// `PERCENT|SPEED|ETA` body. Pure value-in / value-out: no `Process`, no I/O.
enum ProgressParser {

    /// Tokens yt-dlp uses for an unknown/unavailable value (compared case-insensitively).
    private static let unknownTokens: Set<String> = ["n/a", "---", "unknown", ""]

    static func parse(line: String) -> DownloadEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = trimmed.components(separatedBy: "|")
        guard fields.count == 3 else { return nil }
        return .progress(
            percent: parsePercent(fields[0]),
            speed: normalize(fields[1]),
            eta: normalize(fields[2]),
            stage: nil
        )
    }

    /// Trim a field and map yt-dlp's "unknown" tokens to `nil`.
    private static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if unknownTokens.contains(lower) { return nil }
        if lower.hasPrefix("unknown ") { return nil }   // e.g. "Unknown B/s"
        return trimmed
    }

    /// "  12.3%" → 0.123. Unknown / unparseable → `nil`.
    private static func parsePercent(_ raw: String) -> Double? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%") { trimmed.removeLast() }
        guard let value = normalize(trimmed), let number = Double(value) else { return nil }
        return number / 100.0
    }
}
