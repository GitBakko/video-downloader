import Foundation

/// One released version parsed from `CHANGELOG.md`.
public struct ChangelogRelease: Identifiable, Equatable, Sendable {
    public var id: String { version }
    public let version: String          // e.g. "1.2.0" or "Unreleased"
    public let date: String?            // e.g. "2026-07-03"
    public let sections: [ChangelogSection]

    public init(version: String, date: String?, sections: [ChangelogSection]) {
        self.version = version
        self.date = date
        self.sections = sections
    }
}

/// A group of bullets under a version, e.g. "Added" / "Changed" / "Fixed".
public struct ChangelogSection: Identifiable, Equatable, Sendable {
    public var id: String { heading }
    public let heading: String
    public let items: [String]          // bullet texts (may contain inline Markdown)

    public init(heading: String, items: [String]) {
        self.heading = heading
        self.items = items
    }
}

/// Parses a "Keep a Changelog"-style Markdown document into releases. Pure —
/// no I/O — so the app can bundle `CHANGELOG.md` and render it, and we can test
/// the parsing deterministically.
public enum ChangelogParser {

    public static func parse(_ markdown: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []

        var currentVersion: String?
        var currentDate: String?
        var sections: [ChangelogSection] = []

        var sectionHeading: String?
        var bullets: [String] = []

        func flushSection() {
            if let heading = sectionHeading, !bullets.isEmpty {
                sections.append(ChangelogSection(heading: heading, items: bullets))
            }
            sectionHeading = nil
            bullets = []
        }
        func flushRelease() {
            flushSection()
            if let version = currentVersion {
                releases.append(ChangelogRelease(version: version, date: currentDate, sections: sections))
            }
            currentVersion = nil; currentDate = nil; sections = []
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = rawLine

            if let (version, date) = parseVersionHeader(line) {
                flushRelease()
                currentVersion = version
                currentDate = date
                continue
            }
            // Only parse content once we're inside a version block.
            guard currentVersion != nil else { continue }

            if let heading = parseSectionHeader(line) {
                flushSection()
                sectionHeading = heading
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                bullets.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if !trimmed.isEmpty, !bullets.isEmpty, !trimmed.hasPrefix("<!--"), !trimmed.hasPrefix("_") {
                // A wrapped continuation line for the current bullet — join it.
                bullets[bullets.count - 1] += " " + trimmed
            }
        }
        flushRelease()
        return releases
    }

    /// `## [1.2.0] - 2026-07-03` or `## [Unreleased]` → ("1.2.0", "2026-07-03") / ("Unreleased", nil).
    private static func parseVersionHeader(_ line: String) -> (version: String, date: String?)? {
        guard line.hasPrefix("## ["),
              let open = line.firstIndex(of: "["),
              let close = line.firstIndex(of: "]") else { return nil }
        let version = String(line[line.index(after: open)..<close])
        var date: String?
        if let dash = line.range(of: " - ", range: close..<line.endIndex) {
            let rest = line[dash.upperBound...].trimmingCharacters(in: .whitespaces)
            date = rest.isEmpty ? nil : rest
        }
        return (version, date)
    }

    /// `### Added` → "Added".
    private static func parseSectionHeader(_ line: String) -> String? {
        guard line.hasPrefix("### ") else { return nil }
        return String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
    }
}
