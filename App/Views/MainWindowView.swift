import SwiftUI
import AppKit
import VideoDownloaderCore

struct MainWindowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        @Bindable var settings = app.settings

        VStack(spacing: 0) {
            // Add bar + default format
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Incolla uno o più URL…", text: $app.urlField, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .onSubmit { app.addFromField() }
                    Button("Aggiungi") { app.addFromField() }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(app.urlField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack(spacing: 8) {
                    Text("Formato di default:").foregroundStyle(.secondary)
                    FormatPresetPicker(choice: $settings.defaultFormat)
                    Spacer()
                }
            }
            .padding(12)

            Divider()

            // Destination + queue controls
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .accessibilityHidden(true)
                Text(settings.destination.path(percentEncoded: false))
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Button("Cambia…") { chooseDestination() }
                    .controlSize(.small)
                Spacer()
                Button { app.queue.togglePauseQueue() } label: {
                    Label(app.queue.isQueuePaused ? "Riprendi coda" : "Pausa coda",
                          systemImage: app.queue.isQueuePaused ? "play.fill" : "pause.fill")
                }
                .controlSize(.small)
                .accessibilityValue(app.queue.isQueuePaused ? "in pausa" : "in esecuzione")
                Button { app.queue.startAll() } label: {
                    Label("Scarica tutti", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!app.queue.items.contains { $0.state == .ready })
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let destinationError = app.destinationError {
                // Clear, app-side message when the folder can't be written to (P16).
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                    Text(destinationError)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider()

            list
        }
    }

    private var list: some View {
        Group {
            if app.queue.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(app.queue.items, id: \.id) { item in
                            DownloadRowView(
                                item: item,
                                queue: app.queue,
                                reveal: { app.revealInFinder($0) },
                                onUpdateYtDlp: { app.updateYtDlp() }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Nessun download").foregroundStyle(.secondary)
            Text("Incolla un URL e premi Aggiungi.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = app.settings.destination
        panel.prompt = "Scegli"
        if panel.runModal() == .OK, let url = panel.url {
            app.settings.destination = url
        }
    }
}
