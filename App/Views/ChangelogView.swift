import SwiftUI
import AppKit
import VideoDownloaderCore

/// In-app release history — the bundled `CHANGELOG.md`, parsed by version.
struct ChangelogView: View {
    @State private var releases: [ChangelogRelease] = []
    @State private var loaded = false

    private var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if loaded && releases.isEmpty {
                    Text("Cronologia delle versioni non disponibile.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(releases) { release in
                        releaseBlock(release)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 500, minHeight: 560)
        .task { load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Novità").font(.title2).bold()
                Text("Versione attuale: \(currentVersion)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func releaseBlock(_ release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(release.version == "Unreleased" ? "In arrivo" : "v\(release.version)")
                    .font(.title3).bold()
                if let date = release.date {
                    Text(date).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if release.version == currentVersion {
                    Text("attuale")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                        .foregroundStyle(Color.accentColor)
                }
            }

            ForEach(release.sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedHeading(section.heading))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(section.items, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("•").foregroundStyle(.tint)
                            Text(.init(item))    // inline Markdown: **bold**, *italic*, `code`
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Divider()
        }
    }

    private func localizedHeading(_ heading: String) -> String {
        switch heading.lowercased() {
        case "added":      return "Aggiunto"
        case "changed":    return "Modificato"
        case "fixed":      return "Corretto"
        case "removed":    return "Rimosso"
        case "deprecated": return "Deprecato"
        case "security":   return "Sicurezza"
        default:           return heading
        }
    }

    private func load() {
        defer { loaded = true }
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        releases = ChangelogParser.parse(text)
    }
}
