import Foundation

final class DownloadEngine {

    /// Extracts the destination file URL from a yt-dlp stdout line, if present.
    /// Handles the common shapes:
    ///   `[download] Destination: /path/File.mp4`
    ///   `[ExtractAudio] Destination: /path/File.mp3`
    ///   `[Merger] Merging formats into "/path/File.mkv"`
    ///   `[download] /path/File.mp4 has already been downloaded`
    static func destination(from line: String) -> URL? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let range = trimmed.range(of: "Destination: ") {
            let path = String(trimmed[range.upperBound...])
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        if let range = trimmed.range(of: "Merging formats into \"") {
            let rest = trimmed[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") {
                return URL(fileURLWithPath: String(rest[..<end]))
            }
        }
        if trimmed.hasPrefix("[download] "),
           let end = trimmed.range(of: " has already been downloaded")?.lowerBound {
            let start = trimmed.index(trimmed.startIndex, offsetBy: "[download] ".count)
            let path = String(trimmed[start..<end])
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        return nil
    }
}
