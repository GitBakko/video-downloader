import Foundation
import NaturalLanguage

/// Builds the final, human-readable filename of a finished download:
/// `<Performer>_<clean title>.<ext>`.
///
/// The performer is resolved against the user's library — one folder per
/// performer — because on X the name is usually just written in the tweet text,
/// neither the posting account (often an aggregator) nor an @mention. Order:
/// 1. the first metadata `cast` name that matches a library folder;
/// 2. the first library folder name found (whole words) in the tweet/title text;
/// 3. the first `cast` name;
/// 4. the first person name NLTagger spots in the text;
/// 5. `"vario"`.
/// Pure logic apart from `libraryNames(at:)` ⇒ unit-tested in `FileNamerTests`.
public enum FileNamer {

    /// Defaults for `SettingsStore.performerLibrary` / `.performerExclusions`.
    public static let defaultLibraryPath = "/Volumes/Disco dati 3/cartella senza nome"
    public static let defaultExclusions = ["Compilations", "Telegram"]
    public static let fallbackPerformer = "vario"
    static let maxTitleLength = 120

    /// Folder names directly under `path` (the performer library) minus the
    /// `excluding` ones (case-insensitive), or `[]` when the disk isn't mounted.
    public static func libraryNames(at path: String, excluding: [String] = [],
                                    fileManager: FileManager = .default) -> [String] {
        let excluded = Set(excluding.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let entries = (try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { !excluded.contains($0.lowercased()) }
            .sorted()
    }

    /// `"<Performer>_<clean title>.<ext>"` for `item`, given the library folder names.
    public static func fileName(for item: DownloadItem, ext: String, library: [String]) -> String {
        let rawTitle = item.title ?? ""
        // yt-dlp cuts X titles with "..."; the full tweet text is the better title.
        let titleSource = isTruncated(rawTitle) && !(item.description ?? "").isEmpty
            ? item.description! : rawTitle
        let text = [item.description, dropTruncatedWord(rawTitle)].compactMap { $0 }.joined(separator: "\n")
        let who = performer(cast: item.cast, text: text, library: library)
        var title = cleanTitle(titleSource, uploader: item.uploader)
        // Don't repeat the name that is already the prefix, nor leave its debris
        // ("Adriana Chechik's Gangbang" → "Gangbang", "Peta Jensen - Brazzers" → "Brazzers").
        title = collapse(title.replacingOccurrences(of: who, with: " ", options: [.caseInsensitive]))
        title = title.replacingOccurrences(of: #"^'s\b"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-,'"))
        if title.isEmpty { title = "video" }
        return ext.isEmpty ? "\(who)_\(title)" : "\(who)_\(title).\(ext)"
    }

    static func performer(cast: [String], text: String, library: [String]) -> String {
        let libraryByKey = Dictionary(library.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        if let hit = cast.lazy.compactMap({ libraryByKey[key($0)] }).first { return hit }

        // Links carry random slugs (`t.co/TriZk5Mr6Y`) that look like names: drop them.
        let text = text.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
        // Hashtags carry names too: `#PetaJensen` → "Peta Jensen"; a lowercase
        // `#petajensen` is caught by the space-less form of the folder name.
        let haystack = " " + words(splitHashtags(text)) + " "
        let found = library
            .compactMap { name -> (String, String.Index)? in
                let spaced = words(name)
                guard !spaced.isEmpty else { return nil }
                let compact = spaced.replacingOccurrences(of: " ", with: "")
                let hits = [spaced, compact].compactMap { haystack.range(of: " \($0) ")?.lowerBound }
                return hits.min().map { (name, $0) }
            }
            .min { $0.1 < $1.1 }   // earliest mention in the text wins
        if let found { return found.0 }

        if let first = cast.lazy.map(ascii).map(collapse).first(where: { !$0.isEmpty }) { return first }
        if let name = personNames(in: splitHashtags(text)).first { return name }
        return fallbackPerformer
    }

    /// Readable title: ASCII only, no emoji / links / hashtags / @handles /
    /// bracketed ids / random-looking codes, single spaces.
    static func cleanTitle(_ raw: String, uploader: String?) -> String {
        var s = dropTruncatedWord(raw)
        // yt-dlp titles X posts "<account> - <tweet>"; the account is noise.
        if let uploader, !uploader.isEmpty, s.hasPrefix(uploader + " - ") {
            s.removeFirst(uploader.count + 3)
        }
        s = s.replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[#@]\w+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        s = ascii(s)
        s = s.replacingOccurrences(of: #"[^A-Za-z0-9 '&(),.!-]"#, with: " ", options: .regularExpression)
        s = collapse(s.split(separator: " ").filter { !isCode($0) }.joined(separator: " "))
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " .-,"))
        if s.count > maxTitleLength {
            s = String(s.prefix(maxTitleLength))
            if let space = s.lastIndex(of: " ") { s = String(s[..<space]) }
        }
        return s
    }

    /// Tokens that only make a name unreadable: letters+digits mixed (≥ 6 chars,
    /// e.g. `a8F3k2Lq`) or long digit runs (≥ 6, e.g. ids/timestamps). Keeps
    /// `1080p`, `4K`, `69`.
    /// ponytail: shape heuristic; letters-only gibberish (`asdadsad`) survives.
    static func isCode(_ token: Substring) -> Bool {
        let t = token.trimmingCharacters(in: .punctuationCharacters)
        guard t.count >= 6 else { return false }
        let hasDigit = t.contains(where: \.isNumber)
        return hasDigit && (t.contains(where: \.isLetter) || t.allSatisfy(\.isNumber))
    }

    static func isTruncated(_ s: String) -> Bool { s.hasSuffix("...") || s.hasSuffix("…") }

    /// A title cut with "..." ends mid-word ("compilation, f..."): drop that stub.
    static func dropTruncatedWord(_ s: String) -> String {
        guard isTruncated(s) else { return s }
        let body = s.trimmingCharacters(in: CharacterSet(charactersIn: ".…"))
        guard let space = body.lastIndex(where: \.isWhitespace) else { return body }
        return String(body[..<space])
    }

    /// `#PetaJensen` → `Peta Jensen`: camel-case split inside hashtags only
    /// (splitting every word would turn `McKenzie` or slugs into fake names).
    static func splitHashtags(_ s: String) -> String {
        let regex = try! NSRegularExpression(pattern: #"#(\w+)"#)
        var out = s
        for match in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let whole = Range(match.range, in: s), let tag = Range(match.range(at: 1), in: s) else { continue }
            let split = String(s[tag]).replacingOccurrences(
                of: #"(?<=\p{Ll})(?=\p{Lu})"#, with: " ", options: .regularExpression)
            out.replaceSubrange(whole, with: split)
        }
        return out
    }

    static func personNames(in text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var names: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if tag == .personalName {
                var name = collapse(ascii(String(text[range])))
                // NLTagger often stops at the first name ("lusting for Ava"): complete
                // it from a "Ava Addams" elsewhere in the text. Lone words are mostly
                // noise ("Satan", brands), so an uncompleted one is dropped.
                if !name.contains(" ") { name = completedName(name, in: text) ?? "" }
                // Real names are letters only: rejects slugs and codes.
                if name.range(of: #"^[A-Z][A-Za-z'-]+( [A-Z][A-Za-z'-]+)+$"#, options: .regularExpression) != nil,
                   !names.contains(name) {
                    names.append(name)
                }
            }
            return true
        }
        return names
    }

    /// `"Ava"` → `"Ava Addams"` when the text has the first name followed by a capitalized word.
    static func completedName(_ first: String, in text: String) -> String? {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: first) + #" ([A-Z][a-z]+)\b"#
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return collapse(ascii(String(text[r])))
    }

    /// Picks `<dir>/<name>`, or `<dir>/<stem>_2.<ext>`, `_3`… so nothing is overwritten.
    public static func uniqueURL(in dir: URL, name: String, fileManager: FileManager = .default) -> URL {
        let first = dir.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: first.path) else { return first }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for n in 2... {
            let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(stem)_\(n)" : "\(stem)_\(n).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return first   // unreachable
    }

    // MARK: - Text helpers

    static func ascii(_ s: String) -> String {
        s.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? s
    }

    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Lowercase ASCII words separated by single spaces — for matching.
    private static func words(_ s: String) -> String {
        collapse(ascii(s).lowercased().replacingOccurrences(of: #"[^a-z0-9]"#, with: " ",
                                                            options: .regularExpression))
    }

    private static func key(_ s: String) -> String { words(s) }
}
