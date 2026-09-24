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

                Stepper(value: $settings.maxConcurrentDownloads, in: 1...8) {
                    LabeledContent("Download contemporanei (totale)",
                                   value: "\(settings.maxConcurrentDownloads)")
                }
                Stepper(value: $settings.maxConcurrentPerSource, in: 1...8) {
                    LabeledContent("Contemporanei per singola fonte",
                                   value: "\(settings.maxConcurrentPerSource)")
                }
                Text("Quanti download possono partire insieme in tutta l’app e quanti dallo stesso sito (per non sovraccaricare una singola fonte).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Nomi dei file") {
                LabeledContent("Cartella attrici") {
                    HStack {
                        Text(settings.performerLibrary.path(percentEncoded: false))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Cambia…") { choosePerformerLibrary() }
                    }
                }
                TextField("Cartelle da ignorare", text: Binding(
                    get: { settings.performerExclusions.joined(separator: ", ") },
                    set: { settings.performerExclusions = $0.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty } }
                ))
                Text("A download finito il file diventa “<Attrice>_<titolo>”. Il nome viene cercato tra le sottocartelle della cartella attrici (escluse quelle da ignorare, separate da virgola), poi nei metadati e nel testo del post; altrimenti “vario”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Sposta nella cartella dell’attrice", isOn: $settings.movesToPerformerFolder)
                Text("A download finito o dopo “Rinomina…”, i file il cui nome è una sottocartella della cartella attrici vengono spostati lì (con il disco montato). I “vario” restano nella destinazione.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("File già scaricati") {
                    HStack(spacing: 8) {
                        if let progress = app.renameProgress {
                            ProgressView().controlSize(.small)
                            Text("\(progress.done)/\(progress.total)").foregroundStyle(.secondary)
                        }
                        Button("Rinomina…") { confirmingRename = true }
                            .disabled(app.renameProgress != nil || app.hasActiveDownloads)
                    }
                }
                Text("Rinomina i file della destinazione che hanno ancora il nome originale (“Titolo [id]”), rileggendo i metadati dal link salvato in cronologia. Disponibile quando nessun download è in corso.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Extra") {
                Toggle("Incorpora copertina e metadati", isOn: $settings.embedThumbnailAndMetadata)
            }

            Section("Contenuti che richiedono il login") {
                Picker("Usa i cookie di", selection: $settings.cookiesBrowser) {
                    Text("Nessuno").tag(String?.none)
                    ForEach(CookieBrowser.allCases, id: \.rawValue) { browser in
                        Text(browser.displayName).tag(String?.some(browser.rawValue))
                    }
                }
                Text("I post con contenuti sensibili (X, YouTube con limiti di età, Instagram) non mostrano il video a chi non ha effettuato l’accesso: yt-dlp risponde “No video could be found”. Scegliendo un browser in cui hai già fatto login, l’app riusa i suoi cookie. macOS chiederà una conferma (Portachiavi per i browser Chromium, Accesso completo al disco per Safari).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .confirmationDialog(renameTitle, isPresented: $confirmingRename) {
            Button("Rinomina") { app.renameExistingFiles() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(app.settings.movesToPerformerFolder
                 ? "I file vengono rinominati sul disco, poi quelli con un’attrice della cartella attrici vengono spostati nella sua sottocartella."
                 : "I file vengono rinominati sul disco. Quelli già rinominati non vengono toccati.")
        }
    }

    @State private var confirmingRename = false

    private var renameTitle: String {
        let count = app.renameCandidates().count
        if app.settings.movesToPerformerFolder && count == 0 { return "Spostare i file nelle cartelle delle attrici?" }
        return count == 0 ? "Nessun file da rinominare" : "Rinominare \(count) file in “\(app.settings.destination.lastPathComponent)”?"
    }

    private func choosePerformerLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = app.settings.performerLibrary
        panel.prompt = "Scegli"
        if panel.runModal() == .OK, let url = panel.url {
            app.settings.performerLibrary = url
            app.performerLibraryMissing = false
        }
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
