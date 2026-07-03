import SwiftUI
import AppKit
import VideoDownloaderCore

struct MainWindowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        @Bindable var settings = app.settings

        VStack(spacing: 0) {
            // S2: a slim add-bar just above the list — a multi-line URL field is
            // awkward inside a window toolbar, so it lives here as a top header.
            addBar

            if let destinationError = app.destinationError {
                destinationBanner(destinationError)
            }

            Divider()

            list
        }
        // S2: destination + queue controls now read as real Mac window chrome
        // instead of hand-built Divider-separated content rows.
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { chooseDestination() } label: {
                    Label(settings.destination.lastPathComponent, systemImage: "folder")
                }
                .help("Salva in: \(settings.destination.path(percentEncoded: false))\nClic per scegliere un'altra cartella")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button { app.queue.togglePauseQueue() } label: {
                    Label(app.queue.isQueuePaused ? "Riprendi coda" : "Pausa coda",
                          systemImage: app.queue.isQueuePaused ? "play.fill" : "pause.fill")
                }
                .help(app.queue.isQueuePaused ? "Riprendi la coda dei download" : "Metti in pausa la coda dei download")
                .accessibilityValue(app.queue.isQueuePaused ? "in pausa" : "in esecuzione")

                downloadAllButton
            }
        }
    }

    // MARK: Add bar (S2 / S3)

    private var addBar: some View {
        @Bindable var app = app
        @Bindable var settings = app.settings

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Incolla uno o più URL…", text: $app.urlField, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit { app.addFromField() }
                // S3: the entry action is the primary one on this bar.
                Button("Aggiungi") { app.addFromField() }
                    .buttonStyle(.borderedProminent)
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
    }

    // MARK: Queue controls (S3)

    /// "Scarica tutti" is prominent only when it's the obvious next step — there
    /// are `.ready` items *and* the URL field is empty — so it never competes with
    /// the filled "Aggiungi" button while the user is still pasting links (S3).
    @ViewBuilder
    private var downloadAllButton: some View {
        let hasReady = app.queue.items.contains { $0.state == .ready }
        let emphasize = hasReady && app.urlField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let button = Button { app.queue.startAll() } label: {
            Label("Scarica tutti", systemImage: "arrow.down.circle.fill")
        }
        .disabled(!hasReady)
        .help("Metti in coda e scarica tutti gli elementi pronti")

        if emphasize {
            button.buttonStyle(.borderedProminent)
        } else {
            button
        }
    }

    // MARK: Destination write-error banner (P16, preserved)

    private func destinationBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: List (S1 — native List for keyboard nav / focus / separators)

    private var list: some View {
        Group {
            if app.queue.items.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(app.queue.items, id: \.id) { item in
                        DownloadRowView(
                            item: item,
                            queue: app.queue,
                            destination: app.settings.destination,
                            reveal: { app.revealInFinder($0) },
                            onUpdateYtDlp: { app.updateYtDlp() }
                        )
                    }
                }
                .listStyle(.inset)
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
