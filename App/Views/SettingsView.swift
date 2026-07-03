import SwiftUI
import AppKit
import VideoDownloaderCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings

        Form {
            Section("Destinazione") {
                HStack {
                    Text(settings.destination.path(percentEncoded: false))
                        .lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cambia…") { chooseDestination() }
                }
            }

            Section("Formato di default") {
                FormatPresetPicker(choice: $settings.defaultFormat)
            }

            Section("Download") {
                Toggle("Avvia i download automaticamente", isOn: $settings.autoStartDownloads)
                Text("Quando è attivo, un link incollato o rilevato dagli appunti parte da solo, senza premere “Scarica”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Extra") {
                Toggle("Incorpora copertina e metadati", isOn: $settings.embedThumbnailAndMetadata)
            }

            Section("Componenti") {
                LabeledContent("yt-dlp") {
                    HStack(spacing: 8) {
                        // Read the observable mirror on AppModel so the version
                        // refreshes after warm-up / update (M7).
                        Text(app.ytDlpVersion ?? "sconosciuta")
                            .foregroundStyle(.secondary)
                        if app.updatingYtDlp { ProgressView().controlSize(.small) }
                        Button("Aggiorna") { app.updateYtDlp() }
                            .disabled(app.updatingYtDlp)
                    }
                }
                if let updateError = app.updateError {
                    // Surface a failed update instead of swallowing it (M2).
                    Text(updateError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
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
