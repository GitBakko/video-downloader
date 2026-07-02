import Foundation

/// Turns raw yt-dlp stdout lines into `DownloadEvent`s (spec §6 `--progress-template`).
/// yt-dlp strips the `download:` type prefix, so lines arrive as the bare
/// `PERCENT|SPEED|ETA` body. Pure value-in / value-out: no `Process`, no I/O.
enum ProgressParser {

    /// Parse a single `--progress-template` line: `PERCENT|SPEED|ETA`.
    static func parse(line: String) -> DownloadEvent? {
        let fields = line.components(separatedBy: "|")
        guard fields.count == 3 else { return nil }
        return .progress(
            percent: parsePercent(fields[0]),
            speed: trimmedField(fields[1]),
            eta: trimmedField(fields[2]),
            stage: nil
        )
    }

    private static func trimmedField(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
    }

    /// "  12.3%" → 0.123. Unparseable → nil.
    private static func parsePercent(_ raw: String) -> Double? {
        var trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%") { trimmed.removeLast() }
        return Double(trimmed).map { $0 / 100.0 }
    }
}
