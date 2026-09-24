import Foundation

/// Applies `FileNamer` to files downloaded before automatic renaming existed.
///
/// Touched: files still carrying the app's original template (`Title [id].ext`),
/// which this app produced and never renamed, plus earlier `vario_…` results — a
/// second pass that retries them (new library folders, better extraction) and
/// renames them only if a performer is found now. Nothing else in the folder moves.
/// Metadata comes from re-probing the URL recorded in the history (tweet text,
/// cast); without a history record, or when the probe fails (deleted post,
/// offline), the title embedded in the filename is used instead.
public enum ExistingFileRenamer {

    public struct Candidate: Equatable, Sendable {
        public let file: URL
        /// nil for a `vario_…` retry (the id is no longer in the name).
        public let mediaID: String?
        /// Title as it appears in the filename, used when no probe is possible.
        public let fileTitle: String
    }

    public struct Rename: Equatable, Sendable {
        public let from: URL
        public let to: URL
    }

    /// Finished app-template files in `directory`. Skips partials (`.part`/`.ytdl`)
    /// and yt-dlp's intermediate per-format files (`….f137.mp4`, `….temp.mp4`),
    /// which belong to a download still in flight or awaiting a merge.
    public static func candidates(in directory: URL, fileManager: FileManager = .default) -> [Candidate] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.sorted().compactMap { name in
            if name.hasPrefix(variousPrefix) { return retryCandidate(directory, name, fileManager) }
            guard !name.hasPrefix("."),
                  !name.hasSuffix(".part"), !name.hasSuffix(".ytdl"),
                  name.range(of: #"\.(f\d+|temp)\.[^.]+$"#, options: .regularExpression) == nil,
                  let id = PartialScanner.lastBracketID(name),
                  let bracket = name.range(of: "[\(id)]", options: .backwards)
            else { return nil }
            let file = directory.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue
            else { return nil }
            let title = String(name[..<bracket.lowerBound]).trimmingCharacters(in: .whitespaces)
            return Candidate(file: file, mediaID: id, fileTitle: title)
        }
    }

    static let variousPrefix = FileNamer.fallbackPerformer + "_"

    /// `vario_<title>[_N].ext` → a candidate whose title is `<title>`.
    private static func retryCandidate(_ directory: URL, _ name: String, _ fileManager: FileManager) -> Candidate? {
        let file = directory.appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue,
              !name.hasSuffix(".part"), !name.hasSuffix(".ytdl") else { return nil }
        let stem = (String(name.dropFirst(variousPrefix.count)) as NSString).deletingPathExtension
        let title = stem.replacingOccurrences(of: #"_\d+$"#, with: "", options: .regularExpression)
        return Candidate(file: file, mediaID: nil, fileTitle: title)
    }

    /// Renames every candidate, one at a time. `urlFor` maps a file to the page URL
    /// it was downloaded from (history lookup). Reports `(done, total)` after each
    /// file and returns what was actually moved.
    @MainActor
    public static func renameAll(
        _ candidates: [Candidate],
        library: [String],
        prober: MediaProbing,
        cookiesBrowser: String?,
        urlFor: (URL) -> String?,
        onProgress: (Int, Int) -> Void = { _, _ in },
        fileManager: FileManager = .default
    ) async -> [Rename] {
        var renames: [Rename] = []
        for (index, candidate) in candidates.enumerated() {
            if Task.isCancelled { break }
            let item = await metadata(for: candidate, url: urlFor(candidate.file),
                                      prober: prober, cookiesBrowser: cookiesBrowser)
            let name = FileNamer.fileName(for: item, ext: candidate.file.pathExtension, library: library)
            // A retry that still finds nobody stays as it is (no churn to `vario_x_2`).
            if candidate.mediaID == nil && name.hasPrefix(variousPrefix) {
                onProgress(index + 1, candidates.count)
                continue
            }
            let target = FileNamer.uniqueURL(in: candidate.file.deletingLastPathComponent(),
                                             name: name, fileManager: fileManager)
            if (try? fileManager.moveItem(at: candidate.file, to: target)) != nil {
                renames.append(Rename(from: candidate.file, to: target))
            }
            onProgress(index + 1, candidates.count)
        }
        return renames
    }

    /// The probed entry matching the file's media id (a multi-video post yields
    /// several), else a bare item carrying the filename's title.
    static func metadata(for candidate: Candidate, url: String?,
                         prober: MediaProbing, cookiesBrowser: String?) async -> DownloadItem {
        // X media ids are long numbers and X titles read "<account> - <tweet>":
        // recover the account so `FileNamer` drops it like it does after a probe.
        let isXLike = (candidate.mediaID ?? "").count >= 15 && candidate.mediaID!.allSatisfy(\.isNumber)
        let uploader = isXLike ? candidate.fileTitle.components(separatedBy: " - ").first : nil
        let fallback = DownloadItem(url: url ?? "", title: candidate.fileTitle,
                                    mediaID: candidate.mediaID, uploader: uploader)
        guard let url, let items = try? await prober.probe(url: url, cookiesBrowser: cookiesBrowser)
        else { return fallback }
        return items.first { $0.mediaID != nil && $0.mediaID == candidate.mediaID } ?? items.first ?? fallback
    }
}
