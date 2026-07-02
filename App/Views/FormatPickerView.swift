import SwiftUI
import VideoDownloaderCore

// MARK: - UI helpers for FormatChoice

enum FormatKind: String, CaseIterable, Identifiable {
    case video = "Video"
    case audio = "Audio"
    var id: String { rawValue }
}

extension VideoQuality {
    var uiLabel: String {
        switch self {
        case .best:  return "Migliore"
        case .p1080: return "1080p"
        case .p720:  return "720p"
        case .p480:  return "480p"
        }
    }
    static var uiOrder: [VideoQuality] { [.best, .p1080, .p720, .p480] }
}

extension FormatChoice {
    var uiKind: FormatKind {
        switch self {
        case .video:    return .video
        case .audio:    return .audio
        case .specific: return .video
        }
    }
    var uiVideoQuality: VideoQuality {
        if case .video(let q) = self { return q }
        return .best
    }
    var uiSpecificID: String? {
        if case .specific(let id) = self { return id }
        return nil
    }
}

// MARK: - Reusable preset picker (writes through the binding)

struct FormatPresetPicker: View {
    @Binding var choice: FormatChoice
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Picker("", selection: kindBinding) {
                ForEach(FormatKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()

            if choice.uiKind == .video {
                Picker("", selection: videoQualityBinding) {
                    ForEach(VideoQuality.uiOrder, id: \.self) { Text($0.uiLabel).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
            } else {
                Label("MP3 (migliore)", systemImage: "music.note")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!enabled)
    }

    private var kindBinding: Binding<FormatKind> {
        Binding(
            get: { choice.uiKind },
            set: { newKind in
                switch newKind {
                case .video: choice = .video(choice.uiVideoQuality)
                case .audio: choice = .audio(.best)
                }
            }
        )
    }

    private var videoQualityBinding: Binding<VideoQuality> {
        Binding(
            get: { choice.uiVideoQuality },
            set: { choice = .video($0) }
        )
    }
}

// MARK: - Per-item picker: presets + full formats table

struct FormatPickerView: View {
    let item: DownloadItem
    let queue: QueueStore

    private var isEditable: Bool { item.state == .ready || item.state == .queued }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormatPresetPicker(choice: choiceBinding, enabled: isEditable)

            if !item.availableFormats.isEmpty {
                DisclosureGroup("Tutti i formati") {
                    formatsTable
                }
                .disabled(!isEditable)
            }

            if !isEditable {
                Text("Il formato non è più modificabile: il download è già iniziato.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var formatsTable: some View {
        VStack(spacing: 0) {
            ForEach(item.availableFormats, id: \.formatID) { fmt in
                Button {
                    queue.setFormat(.specific(formatID: fmt.formatID), for: item.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.selectedFormat.uiSpecificID == fmt.formatID
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(.tint)
                        Text(fmt.formatID).frame(width: 60, alignment: .leading).monospaced()
                        Text(fmt.resolution ?? "—").frame(width: 66, alignment: .leading)
                        Text(fmt.ext).frame(width: 56, alignment: .leading)
                        Text(codecSummary(fmt)).frame(width: 160, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(fileSize(fmt.filesize)).frame(width: 80, alignment: .trailing)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .font(.caption)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private var choiceBinding: Binding<FormatChoice> {
        Binding(
            get: { item.selectedFormat },
            set: { queue.setFormat($0, for: item.id) }
        )
    }

    private func codecSummary(_ f: MediaFormat) -> String {
        let v = f.vcodec ?? "none"
        let a = f.acodec ?? "none"
        if v != "none" && a == "none" { return "video \(v) (muto)" }
        if v == "none" && a != "none" { return "audio \(a)" }
        return "\(v) / \(a)"
    }

    private func fileSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
