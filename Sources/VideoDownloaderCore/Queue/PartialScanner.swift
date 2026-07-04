import Foundation

/// Finds the leftover yt-dlp partial-download files in the destination folder so
/// the app can offer to resume or delete them after a quit/crash. yt-dlp names its
/// temp files `<final name>.part`, `<final name>.ytdl`, and (for fragmented or
/// separate video+audio streams) `<final name>.part-FragN.part` — all of which
/// carry the media id in the `… [id].ext` filename the app's output template
/// produces. Pure logic (only reads a directory listing) ⇒ unit-testable.
public enum PartialScanner {

    /// One interrupted download: all the temp files that share a media id.
    public struct Partial: Identifiable, Equatable, Sendable {
        public var id: String { mediaID ?? files.first?.lastPathComponent ?? baseName }
        /// A human-ish name for the row when there's no queue record to name it —
        /// the final filename with the `.part`/`.ytdl` bits stripped.
        public let baseName: String
        /// yt-dlp media id parsed from `… [id].ext`, if present. Links to a record.
        public let mediaID: String?
        public let files: [URL]
        public let totalSize: Int64

        public init(baseName: String, mediaID: String?, files: [URL], totalSize: Int64) {
            self.baseName = baseName; self.mediaID = mediaID
            self.files = files; self.totalSize = totalSize
        }
    }

    private static func isPartial(_ name: String) -> Bool {
        name.hasSuffix(".part") || name.hasSuffix(".ytdl")   // covers `.part-FragN.part` too
    }

    /// Group the temp files in `directory` by media id (falling back to filename
    /// when no `[id]` is present), newest-looking first is not important — sorted
    /// by name for a stable UI.
    public static func scan(directory: URL, fileManager: FileManager = .default) -> [Partial] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        var groups: [String: (base: String, id: String?, files: [URL], size: Int64)] = [:]
        for name in names where isPartial(name) {
            let url = directory.appendingPathComponent(name)
            let size = ((try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int64) ?? 0
            let id = lastBracketID(name)
            let key = id ?? name                              // orphan-without-id keyed by its own name
            var g = groups[key] ?? (base: strippedName(name), id: id, files: [], size: 0)
            g.files.append(url); g.size += size
            groups[key] = g
        }
        return groups.values
            .map { Partial(baseName: $0.base, mediaID: $0.id,
                           files: $0.files.sorted { $0.path < $1.path }, totalSize: $0.size) }
            .sorted { $0.baseName.localizedCaseInsensitiveCompare($1.baseName) == .orderedAscending }
    }

    /// The last `[…]` group in a filename — the app's template puts the media id
    /// there (`Title [id].ext`), and it survives extra `.fNNN` / `.part` suffixes.
    static func lastBracketID(_ name: String) -> String? {
        var id: String?
        var depthStart: String.Index?
        for i in name.indices {
            if name[i] == "[" { depthStart = name.index(after: i) }
            else if name[i] == "]", let s = depthStart, s < i {
                id = String(name[s..<i]); depthStart = nil
            }
        }
        return id.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Strip the transient suffixes so the base name reads like the final file.
    static func strippedName(_ name: String) -> String {
        var s = name
        if let r = s.range(of: #"\.part-Frag\d+\.part$"#, options: .regularExpression) {
            s.removeSubrange(r)
        } else if s.hasSuffix(".part") { s.removeLast(".part".count) }
        else if s.hasSuffix(".ytdl") { s.removeLast(".ytdl".count) }
        return s
    }

    /// Delete the given files, ignoring individual failures; returns how many went.
    @discardableResult
    public static func delete(_ files: [URL], fileManager: FileManager = .default) -> Int {
        files.reduce(0) { count, url in (try? fileManager.removeItem(at: url)) != nil ? count + 1 : count }
    }
}
