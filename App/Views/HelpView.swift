import SwiftUI
import VideoDownloaderCore

/// Help window: what the app is, how it works, and the list of supported sites.
struct HelpView: View {
    @Environment(AppModel.self) private var app

    @State private var extractors: [String] = []
    @State private var loading = true
    @State private var query = ""
    /// Debounced, off-main filter results published back for display (S13).
    @State private var filtered: [String] = []

    /// A handful of well-known sites, shown as favicon chips (always visible,
    /// even before the full yt-dlp extractor list loads).
    private let popular: [(name: String, host: String)] = [
        ("YouTube", "youtube.com"), ("Vimeo", "vimeo.com"), ("TikTok", "tiktok.com"),
        ("Instagram", "instagram.com"), ("Facebook", "facebook.com"), ("X", "x.com"),
        ("Twitch", "twitch.tv"), ("Reddit", "reddit.com"), ("SoundCloud", "soundcloud.com"),
        ("Dailymotion", "dailymotion.com"), ("Bluesky", "bsky.app"), ("Bilibili", "bilibili.com"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                howItWorks
                popularSites
                supportedSites
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 560)
        .task {
            let list = await app.binaries.listExtractors()
            extractors = list
            filtered = list          // empty query → everything, no flash of "0 di N"
            loading = false
        }
        // Debounce keystrokes (~150ms) and filter ~1800 strings off the main actor
        // so typing never janks the window (S13). `.task(id:)` auto-cancels the
        // previous run when `query` changes again, giving the debounce for free.
        .task(id: query) {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            let q = query.trimmingCharacters(in: .whitespaces)
            let source = extractors
            let result = await Task.detached(priority: .userInitiated) {
                q.isEmpty ? source : source.filter { $0.localizedCaseInsensitiveContains(q) }
            }.value
            if !Task.isCancelled { filtered = result }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Video Downloader").font(.title2).bold()
                    Text("v\(Bundle.main.shortVersion)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Scarica video (o solo l'audio) da quasi ogni sito. Incolli un URL, "
               + "scegli il formato e lo scarichi in una cartella. Sotto il cofano usa "
               + "gli strumenti open-source **yt-dlp** e **ffmpeg**, che l'app gestisce e "
               + "aggiorna da sola.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Come funziona").font(.headline)
            step(1, "Incolla uno o più URL (anche una playlist) e premi Aggiungi.")
            step(2, "Scegli il formato: preset semplici (Video/Audio + qualità) o la tabella completa.")
            step(3, "Premi Scarica (o Scarica tutti). Fino a 2 download in parallelo.")
            step(4, "A fine download ricevi una notifica; “Mostra nel Finder” apre il file.")
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)")
                .font(.caption.bold()).foregroundStyle(.white)
                .padding(3)
                .frame(minWidth: 18, minHeight: 18)   // grows with Dynamic Type instead of clipping (P10)
                .background(Circle().fill(.tint))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var popularSites: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Siti popolari").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(popular, id: \.host) { site in
                    HStack(spacing: 6) {
                        FaviconView(host: site.host, size: 16)
                        Text(site.name).font(.callout).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
        }
    }

    private var supportedSites: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tutti i siti supportati").font(.headline)
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                } else if !extractors.isEmpty {
                    Text("\(filtered.count) di \(extractors.count)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }

            if loading {
                Text("Carico l'elenco da yt-dlp…").font(.callout).foregroundStyle(.secondary)
            } else if extractors.isEmpty {
                Text("Elenco non disponibile finché yt-dlp non è installato (completa prima il primo avvio).")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("Cerca un sito…", text: $query)
                    .textFieldStyle(.roundedBorder)
                // S5: no fixed maxHeight → the list flows in the page's own
                // ScrollView instead of being a hidden nested scroll region that
                // felt truncated. `LazyVStack` keeps it cheap for ~1800 rows.
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered, id: \.self) { name in
                        Text(name)
                            .font(.callout.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                        Divider()
                    }
                }
            }

            Link(destination: URL(string: "https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md")!) {
                // SF Symbol scales with the text instead of the raw "↗" glyph (P5).
                Label("Elenco completo e aggiornato di yt-dlp", systemImage: "arrow.up.right")
            }
            .font(.callout)
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
}
