import Foundation

/// Turns raw yt-dlp stdout lines into `DownloadEvent`s.
///
/// Progress lines come from `--progress-template` (spec §6), with yt-dlp's
/// `download:` type prefix already stripped:
///   " 12.3%|  4.20MiB/s|00:38"
/// Post-processing steps are announced with bracketed tags, e.g.
///   `[Merger] Merging formats into "…"`.
///
/// Pure value-in / value-out: no `Process`, no I/O — fully unit-tested.
enum ProgressParser {

    /// Tokens yt-dlp uses for an unknown/unavailable value (compared case-insensitively).
    private static let unknownTokens: Set<String> = ["n/a", "---", "unknown", ""]

    /// Bracketed post-processor tags meaning "download finished, now processing".
    static let postProcessingMarkers: [String] = [
        "[Merger]", "[VideoRemuxer]", "[ExtractAudio]", "[EmbedThumbnail]", "[Metadata]"
    ]

    static func parse(line: String) -> DownloadEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if isPostProcessing(trimmed) { return .processing }

        let fields = trimmed.components(separatedBy: "|")
        guard fields.count == 3 else { return nil }
        return .progress(
            percent: parsePercent(fields[0]),
            speed: normalize(fields[1]),
            eta: normalize(fields[2]),
            stage: nil
        )
    }

    /// Whether `line` announces a post-processing step (merge/remux/extract/embed/…).
    static func isPostProcessing(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return postProcessingMarkers.contains { trimmed.contains($0) }
    }

    /// Trim a field and map yt-dlp's "unknown" tokens to `nil`.
    private static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if unknownTokens.contains(lower) { return nil }
        if lower.hasPrefix("unknown ") { return nil }   // e.g. "Unknown B/s"
        return trimmed
    }

    /// "  12.3%" → 0.123, clamped to 0…1. Unknown / unparseable → `nil`.
    private static func parsePercent(_ raw: String) -> Double? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%") { trimmed.removeLast() }
        guard let value = normalize(trimmed), let number = Double(value) else { return nil }
        return min(max(number / 100.0, 0.0), 1.0)
    }
}
