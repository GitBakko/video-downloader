import SwiftUI
import VideoDownloaderCore

struct DownloadRowView: View {
    let item: DownloadItem
    let queue: QueueStore
    let reveal: (URL) -> Void
    let onUpdateYtDlp: () -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    sourceBadge
                    Text(item.title ?? item.url)
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    statusLine
                    progressArea
                }
                Spacer(minLength: 8)
                actions
            }

            DisclosureGroup("Formato", isExpanded: $expanded) {
                FormatPickerView(item: item, queue: queue)
                    .padding(.top, 4)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: Thumbnail
    private var thumbnail: some View {
        Group {
            if let url = item.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: placeholderThumb
                    }
                }
            } else {
                placeholderThumb
            }
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.15))
            .overlay(Image(systemName: "film").foregroundStyle(.secondary))
    }

    // MARK: Status + progress
    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle().fill(stateColor).frame(width: 8, height: 8)
            // Generic, state-derived label only — never the raw yt-dlp `item.stage`
            // token (a bv*+ba download resets the bar between the video/audio passes).
            // Colored by state so the status reads at a glance (grey only while probing).
            Text(stateLabel).font(.caption.weight(.medium)).foregroundStyle(stateColor)
        }
    }

    @ViewBuilder
    private var progressArea: some View {
        switch item.state {
        case .downloading:
            VStack(alignment: .leading, spacing: 2) {
                if let p = item.progress {
                    ProgressView(value: p)
                } else {
                    ProgressView().controlSize(.small)
                }
                HStack(spacing: 10) {
                    Text("Scaricamento…")   // generic label from state, not item.stage
                    if let s = item.speed { Text(s) }
                    if let e = item.eta { Text("ETA \(e)") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        case .processing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Elaborazione…").font(.caption).foregroundStyle(.secondary)
            }
        case .failed:
            if let msg = item.errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text(msg).font(.caption).foregroundStyle(.red).lineLimit(3)
                    if suggestsUpdate(msg) {
                        Button("Aggiorna yt-dlp", action: onUpdateYtDlp).controlSize(.small)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: Actions
    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .trailing, spacing: 6) {
            switch item.state {
            case .ready:
                Button("Scarica") { queue.startDownload(item.id) }
                    .buttonStyle(.borderedProminent)
            case .queued, .downloading, .processing:
                Button(role: .destructive) { queue.cancel(item.id) } label: {
                    Label("Annulla", systemImage: "xmark.circle")
                }
                .controlSize(.small)
            case .completed:
                if let out = item.outputPath {
                    Button { reveal(out) } label: {
                        Label("Mostra nel Finder", systemImage: "magnifyingglass")
                    }
                    .controlSize(.small)
                }
            case .failed, .cancelled:
                Button("Riprova") { queue.retry(item.id) }
                    .controlSize(.small)
            case .probing:
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: Helpers

    /// Favicon of the video's source site + the source name (spec: show the source).
    private var sourceBadge: some View {
        let host = URL(string: item.url)?.host ?? ""
        let label = item.source ?? host.replacingOccurrences(of: "www.", with: "")
        return HStack(spacing: 4) {
            FaviconView(host: host)
            if !label.isEmpty {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private func suggestsUpdate(_ msg: String) -> Bool {
        let m = msg.lowercased()
        return m.contains("update") || m.contains("yt-dlp")
            || m.contains("unable to extract") || m.contains("unsupported url")
    }

    private var stateColor: Color {
        switch item.state {
        case .probing: return .gray
        case .ready: return .teal
        case .queued: return .yellow
        case .downloading: return .blue
        case .processing: return .purple
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private var stateLabel: String {
        switch item.state {
        case .probing: return "Lettura formati…"
        case .ready: return "Pronto"
        case .queued: return "In coda"
        case .downloading: return "Scaricamento"
        case .processing: return "Elaborazione"
        case .completed: return "Completato"
        case .failed: return "Errore"
        case .cancelled: return "Annullato"
        }
    }
}
