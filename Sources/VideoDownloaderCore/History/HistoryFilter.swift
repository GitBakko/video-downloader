import Foundation

/// Pure filtering for the history window — no UI, no state, so it's unit-tested.
///
/// Date bounds are compared inclusively (`>=` / `<=`) against the raw dates; a
/// `nil` bound is unbounded. The view is responsible for widening a "to" bound to
/// the end of its day (and a "from" bound to the start of its day) before calling,
/// so a date-only picker still matches downloads made later that same day.
public enum HistoryFilter {

    public static func filter(
        _ entries: [HistoryEntry],
        source: String? = nil,
        query: String = "",
        downloadedFrom: Date? = nil,
        downloadedTo: Date? = nil,
        addedFrom: Date? = nil,
        addedTo: Date? = nil
    ) -> [HistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            if let source, entry.source != source { return false }

            if !needle.isEmpty {
                let haystack = [entry.title ?? "", entry.url].joined(separator: " ").lowercased()
                if !haystack.contains(needle) { return false }
            }

            if let from = downloadedFrom, entry.completedAt < from { return false }
            if let to = downloadedTo, entry.completedAt > to { return false }
            if let from = addedFrom, entry.addedAt < from { return false }
            if let to = addedTo, entry.addedAt > to { return false }

            return true
        }
    }
}
