import SwiftUI
import AppKit
import VideoDownloaderCore

/// The Cronologia window: a filterable, newest-first log of completed downloads.
struct HistoryView: View {
    @Environment(AppModel.self) private var app

    // Filter state — a `nil`/empty value means "no constraint on this axis".
    @State private var sourceFilter: String?
    @State private var query = ""
    @State private var downloadedFrom: Date?
    @State private var downloadedTo: Date?
    @State private var addedFrom: Date?
    @State private var addedTo: Date?

    private var entries: [HistoryEntry] { app.history.entries }

    /// Distinct sources present in the history, for the source picker.
    private var sources: [String] {
        Array(Set(entries.compactMap(\.source)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The filtered slice, delegating the actual predicate to the Core's pure
    /// `HistoryFilter`. Date-only bounds are widened here (start-of-day for "dal",
    /// end-of-day for "al") so a picked day matches downloads made anytime that day.
    private var filtered: [HistoryEntry] {
        HistoryFilter.filter(
            entries,
            source: sourceFilter,
            query: query,
            downloadedFrom: downloadedFrom.map(Self.startOfDay),
            downloadedTo: downloadedTo.map(Self.endOfDay),
            addedFrom: addedFrom.map(Self.startOfDay),
            addedTo: addedTo.map(Self.endOfDay)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
        }
        .frame(minWidth: 640, idealWidth: 780, maxWidth: .infinity,
               minHeight: 460, idealHeight: 580, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { app.history.clear() } label: {
                    Label("Svuota cronologia", systemImage: "trash")
                }
                .disabled(entries.isEmpty)
                .help("Rimuovi tutte le voci dalla cronologia")
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Fonte", selection: $sourceFilter) {
                    Text("Tutte le fonti").tag(String?.none)
                    ForEach(sources, id: \.self) { source in
                        Text(source).tag(String?.some(source))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)

                TextField("Cerca…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                Spacer()

                Button("Reimposta filtri", action: resetFilters)
                    .disabled(!hasActiveFilters)
            }

            HStack(alignment: .center, spacing: 24) {
                dateRange(title: "Scaricato", from: $downloadedFrom, to: $downloadedTo)
                dateRange(title: "Aggiunto", from: $addedFrom, to: $addedTo)
                Spacer()
            }
            .font(.callout)
        }
        .padding(12)
    }

    private func dateRange(title: String, from: Binding<Date?>, to: Binding<Date?>) -> some View {
        HStack(spacing: 8) {
            Text(title + ":").foregroundStyle(.secondary)
            OptionalDateBound(label: "dal", date: from)
            OptionalDateBound(label: "al", date: to)
        }
    }

    private var hasActiveFilters: Bool {
        sourceFilter != nil || !query.isEmpty
            || downloadedFrom != nil || downloadedTo != nil
            || addedFrom != nil || addedTo != nil
    }

    private func resetFilters() {
        sourceFilter = nil
        query = ""
        downloadedFrom = nil
        downloadedTo = nil
        addedFrom = nil
        addedTo = nil
    }

    // MARK: - Content (list / empty / no-results)

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("\(filtered.count) di \(entries.count)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)

                Divider()

                if filtered.isEmpty {
                    noResults
                } else {
                    List {
                        ForEach(filtered) { entry in
                            HistoryRowView(entry: entry)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nessun download nella cronologia").foregroundStyle(.secondary)
            Text("I download completati appariranno qui.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nessun risultato per i filtri correnti").foregroundStyle(.secondary)
            Button("Reimposta filtri", action: resetFilters)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Date helpers (widen a date-only bound to cover its whole day)

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func endOfDay(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}

/// A single optional date bound: a `.field` DatePicker with a clear button when
/// set, or a link-styled "dal/al" button (that seeds today) when unset (nil).
private struct OptionalDateBound: View {
    let label: String
    @Binding var date: Date?

    var body: some View {
        if let bound = date {
            HStack(spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                DatePicker("", selection: Binding(get: { bound }, set: { date = $0 }),
                           displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                Button { date = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Rimuovi il limite")
            }
        } else {
            Button { date = Date() } label: {
                Label(label, systemImage: "calendar.badge.plus").font(.caption)
            }
            .buttonStyle(.link)
        }
    }
}

/// One history row: favicon + source, thumbnail, title/url, dates + format, and
/// per-row actions (context menu + trailing buttons).
private struct HistoryRowView: View {
    let entry: HistoryEntry
    @Environment(AppModel.self) private var app

    private var fileExists: Bool {
        guard let path = entry.outputPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                sourceBadge
                Text(entry.title ?? entry.url)
                    .font(.headline).lineLimit(2)
                if entry.title != nil {
                    Text(entry.url)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                metadata
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(.vertical, 4)
        .contextMenu { menuContent }
    }

    private var sourceBadge: some View {
        HStack(spacing: 4) {
            FaviconView(host: entry.host ?? "")
            if let source = entry.source, !source.isEmpty {
                Text(source).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 12) {
            Label(entry.formatSummary, systemImage: "film")
            Label("Aggiunto: \(Self.format(entry.addedAt))", systemImage: "tray.and.arrow.down")
            Label("Scaricato: \(Self.format(entry.completedAt))", systemImage: "checkmark.circle")
        }
        .font(.caption2).foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private var thumbnail: some View {
        Group {
            if let thumb = entry.thumbnail, let url = URL(string: thumb) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: 72, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.secondary.opacity(0.15))
            .overlay(Image(systemName: "film").foregroundStyle(.secondary))
    }

    private var actions: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button { app.requeue(entry) } label: {
                Label("Rimetti in coda", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)

            if fileExists {
                Button { app.revealHistoryFile(entry) } label: {
                    Label("Mostra nel Finder", systemImage: "magnifyingglass")
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        Button { app.requeue(entry) } label: {
            Label("Rimetti in coda", systemImage: "arrow.clockwise")
        }
        if fileExists {
            Button { app.revealHistoryFile(entry) } label: {
                Label("Mostra nel Finder", systemImage: "magnifyingglass")
            }
        }
        Divider()
        Button(role: .destructive) { app.history.remove(entry.id) } label: {
            Label("Rimuovi dalla cronologia", systemImage: "trash")
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
