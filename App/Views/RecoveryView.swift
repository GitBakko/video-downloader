import SwiftUI
import VideoDownloaderCore

/// Shown at launch when the destination holds orphaned partial files (`.part`)
/// that belong to no restored queue row — e.g. a download removed while running,
/// or leftovers from before queue persistence. They can only be deleted;
/// interrupted downloads still in the list reappear as resumable rows instead.
struct RecoveryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            List(app.recovery) { item in
                RecoveryRow(item: item)
            }
            .listStyle(.inset)
            Divider()
            footer
        }
        .frame(width: 540, height: 440)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("File parziali residui")
                    .font(.headline)
                Text("\(app.recovery.count) file di download incompleti non appartengono ad alcun elemento in coda. Puoi eliminarli per liberare spazio.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button("Ignora") { app.dismissRecovery() }
            Spacer()
            Button("Elimina tutti", role: .destructive) { app.deleteAllRecovery() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

/// A single orphaned partial: name, leftover filename, partial size, and a
/// Delete action.
private struct RecoveryRow: View {
    @Environment(AppModel.self) private var app
    let item: RecoveryItem

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let detail = item.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let size = item.sizeText {
                    Text("Parziale · \(size)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button(role: .destructive) {
                app.deleteRecovery(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Elimina questi file parziali")
        }
        .padding(.vertical, 4)
    }
}
