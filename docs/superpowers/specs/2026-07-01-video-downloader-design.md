# Video Downloader per macOS — Documento di Design

**Data:** 2026-07-01
**Stato:** Approvato in brainstorming, pronto per il piano di implementazione
**Autore:** bakko (con Claude)

---

## 1. Obiettivo

Un'app **macOS nativa in SwiftUI**, con una singola finestra, che permette di scaricare video (o solo l'audio) da un URL incollato, da praticamente qualunque piattaforma. L'utente incolla uno o più URL (anche playlist), l'app legge i formati disponibili, l'utente conferma *come* scaricare e l'app scarica i file in una cartella.

L'app è un'**interfaccia curata sopra `yt-dlp` + `ffmpeg`**: sono questi due strumenti open-source a fare il lavoro di estrazione, download, unione e conversione. Non si tenta di reimplementare in Swift la logica di estrazione dai singoli siti (irrealistico e fragile).

**Uso:** personale (solo l'autore). Nessuna distribuzione a terzi in v1, quindi nessuna firma/notarizzazione Apple.

**Filosofia:** "semplice semplice". Copre benissimo il caso comune, senza tagliare fuori il controllo fine quando serve.

---

## 2. Decisioni chiave (esito del brainstorming)

| # | Decisione | Scelta |
|---|-----------|--------|
| 1 | Motore di download | Wrapper nativo su **yt-dlp + ffmpeg** |
| 2 | Destinatario | **Solo uso personale** (no notarizzazione/distribuzione) |
| 3 | Gestione dei binari | L'app **si auto-gestisce** yt-dlp e ffmpeg: li scarica al primo avvio, li tiene in una sua cartella, offre "Aggiorna yt-dlp" |
| 4 | Scelta del formato | **Ibrida**: preset semplici (Video/Audio + qualità) di default, con "mostra tutti i formati" (tabella completa) a richiesta |
| 5 | Ambito | **Coda** ordinata con supporto **playlist** (una playlist si espande in tanti item) |
| 6 | Layout finestra | **Formato di default in alto + lista** dei download; ogni riga espandibile per override del formato |
| 7 | Salvataggio | **Cartella fissa** con **nome automatico** dal titolo; cartella modificabile nelle impostazioni |
| 8 | Extra inclusi | **Rileva URL dagli appunti**, **notifica+suono a fine download** (+ "Mostra nel Finder"), **incorpora copertina/metadati** |
| 9 | Extra esclusi | Sottotitoli (fuori dalla v1) |
| 10 | Requisiti | **macOS 14+**, app **non-sandboxed**, **max 2 download in parallelo** |

---

## 3. Architettura

App **non sandboxed** (necessario per lanciare processi esterni e usare la rete senza restrizioni del sandbox), SwiftUI, target **macOS 14+**, struttura MVVM leggera. Cinque componenti con responsabilità nette:

### 3.1 `BinaryManager`
**Cosa fa:** garantisce che yt-dlp e ffmpeg siano presenti ed eseguibili.
- Cartella gestita: `~/Library/Application Support/VideoDownloader/bin/`.
- Al primo avvio (o se mancanti): scarica l'ultima build standalone di **yt-dlp** (`yt-dlp_macos` dalle GitHub Releases del progetto) e una build statica di **ffmpeg** per macOS.
- Rimuove l'attributo di **quarantena Gatekeeper** (`com.apple.quarantine`) dai binari scaricati e imposta il bit di esecuzione, così partono senza blocchi.
- Espone: percorso di yt-dlp, percorso di ffmpeg, versione corrente di yt-dlp, azione **"Aggiorna yt-dlp"** (riscarica l'ultima versione).
- **Dipende da:** rete, filesystem.

### 3.2 `MediaProbe`
**Cosa fa:** dato un URL, ne ricava i metadati e la lista formati **senza scaricare**.
- Esegue `yt-dlp -J --no-warnings <url>` (dump JSON completo). Per le playlist usa il JSON risultante per **espandere** in più `DownloadItem`.
- Ricava: titolo, durata, URL miniatura, ed elenco `formats` (risoluzione, ext, codec video/audio, filesize/approx, tbr, note).
- **Dipende da:** `BinaryManager` (percorso yt-dlp), rete.

### 3.3 `DownloadEngine`
**Cosa fa:** esegue i download e riporta l'avanzamento.
- Per ogni item lancia `yt-dlp` come **`Process`** con gli argomenti costruiti (vedi §6).
- Legge lo stdout con un **`--progress-template`** strutturato (percentuale, byte, velocità, ETA) e/o `--newline`, aggiornando l'item in tempo reale.
- Gestisce la **coda** con concorrenza **massima 2**; gli altri item restano in attesa.
- Passa a yt-dlp: formato scelto, cartella+template di nome, `--ffmpeg-location`, flag per copertina/metadati.
- Supporta **annulla** (termina il processo dell'item) senza toccare gli altri.
- **Dipende da:** `BinaryManager`, `MediaProbe` (formati), filesystem.

### 3.4 `QueueStore` (ViewModel osservabile)
**Cosa fa:** sorgente di verità della UI.
- `@Observable` (o `ObservableObject`) con l'array di `DownloadItem`.
- Coordina probe → attesa → download → completamento/errore.
- Applica il **formato di default** ai nuovi item; consente **override per-item**.
- **Dipende da:** `MediaProbe`, `DownloadEngine`, `SettingsStore`.

### 3.5 `SettingsStore`
**Cosa fa:** preferenze persistenti minime (UserDefaults).
- Cartella di destinazione (default `~/Movies/VideoDownloader`), formato di default (tipo Video/Audio + qualità), toggle degli extra.
- **Dipende da:** UserDefaults.

### 3.6 View (SwiftUI)
- `MainWindowView`: barra di aggiunta URL + barra formato di default + destinazione, e la **lista** dei download.
- `DownloadRowView`: riga con miniatura, titolo, stato/progresso, azioni; espandibile per il **selettore ibrido** dei formati.
- `FormatPickerView`: preset (Video/Audio, qualità) + disclosure "tutti i formati" con tabella.
- `SetupView`: schermata mostrata se i binari mancano o il loro download fallisce.
- `SettingsView`: cartella, formato di default, extra.

---

## 4. Modello dati

```
DownloadItem
├─ id: UUID
├─ url: String
├─ title: String?            // da MediaProbe
├─ thumbnailURL: URL?
├─ duration: TimeInterval?
├─ availableFormats: [MediaFormat]
├─ selectedFormat: FormatChoice   // preset o formato specifico
├─ state: enum { probing, ready, queued, downloading, completed, failed, cancelled }
├─ progress: Double            // 0…1
├─ speed: String?             // es. "4.2 MB/s"
├─ eta: String?              // es. "0:38"
├─ outputPath: URL?
└─ errorMessage: String?

MediaFormat
├─ formatID: String
├─ resolution: String?        // "1080p"
├─ ext: String              // "mp4", "m4a", "webm"
├─ vcodec: String?           // "H.264", "VP9", "none"
├─ acodec: String?
├─ filesize: Int64?          // byte, esatta o approssimata
└─ note: String?

FormatChoice
├─ .preset(kind: {video, audioOnly}, quality: {best, p1080, p720, p480})
└─ .specific(formatID: String)
```

**Persistenza:** la coda vive **in memoria** durante la sessione (nessun ripristino dopo la chiusura in v1). Solo le **impostazioni** (cartella, formato di default, extra) sono persistite in UserDefaults.

---

## 5. Flussi

### 5.1 Primo avvio / bootstrap binari
1. `BinaryManager` verifica la presenza di yt-dlp e ffmpeg.
2. Se mancano → `SetupView` con progresso di download; al termine, rimozione quarantena + bit di esecuzione.
3. Se il download fallisce → messaggio chiaro + "Riprova".

### 5.2 Aggiunta e download
1. L'utente incolla un URL (o l'app lo **pre-compila dagli appunti** se contiene un URL) → *Aggiungi*.
2. `MediaProbe` legge i formati → l'item compare con titolo e miniatura (stato `ready`). Playlist → più item.
3. Vale il **formato di default**; l'utente può espandere la riga e scegliere un preset diverso o un formato specifico (modalità ibrida).
4. Il download parte (automatico o col pulsante ⬇), rispettando il limite di **2 in parallelo**. Barra, velocità, ETA in riga.
5. A fine: **notifica + suono**, copertina/metadati incorporati (se attivo), "Mostra nel Finder". File in `<cartella>/<titolo>.<ext>`.

### 5.3 Aggiornamento di yt-dlp
- Pulsante "Aggiorna yt-dlp" → `BinaryManager` riscarica l'ultima versione e aggiorna l'indicatore di versione.

---

## 6. Interfaccia con yt-dlp (dettagli concreti)

**Probe formati (nessun download):**
```
yt-dlp -J --no-warnings --no-playlist? <url>
```
(playlist gestite espandendo il JSON; `--flat-playlist` come opzione per elenchi lunghi, poi probe per-item alla selezione).

**Download video (best fino a una risoluzione):**
```
yt-dlp -f "bv*[height<=1080]+ba/b[height<=1080]" \
       --ffmpeg-location <ffmpeg> \
       --merge-output-format mp4 \
       --embed-thumbnail --embed-metadata \
       -o "<cartella>/%(title)s.%(ext)s" \
       --newline --progress-template "download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s" \
       <url>
```

**Solo audio → MP3:**
```
yt-dlp -f "ba/b" -x --audio-format mp3 --embed-thumbnail --embed-metadata ...
```

**Formato specifico:** `-f <formatID>` (con eventuale `+bestaudio` per i video-only).

Nota: l'incorporamento di copertina/metadati richiede ffmpeg (già gestito dal `BinaryManager`).

---

## 7. Gestione errori

Regola d'oro: **un download che fallisce non ferma la coda**. Ogni item ha un proprio stato di errore.

| Situazione | Comportamento |
|-----------|---------------|
| Binari mancanti / download binario fallito | `SetupView` con messaggio chiaro + "Riprova" |
| URL non supportato / privato / geobloccato | Item in `failed`, messaggio di yt-dlp reso leggibile |
| yt-dlp obsoleto (sito cambiato) | Errore + suggerimento in evidenza "Aggiorna yt-dlp" |
| Rete interrotta | Item in `failed` con "Riprova"; gli altri proseguono |
| Spazio disco insufficiente | Errore per-item con messaggio esplicito |
| ffmpeg mancante per l'unione | Rilevato prima dell'avvio, non a metà download |

Gli stderr/exit-code di yt-dlp vengono mappati a messaggi umani per i casi più comuni; per gli altri si mostra l'ultima riga significativa di errore.

---

## 8. Strategia di test

**Unit (senza rete, veloci e affidabili):**
- Parsing del JSON di yt-dlp → `[MediaFormat]`, su file di esempio reali salvati come fixture (video singolo, playlist, solo-audio).
- Parsing delle righe di `--progress-template` → percentuale/velocità/ETA.
- Costruzione degli argomenti da `FormatChoice` + impostazioni → array di argomenti corretto.
- Logica di coda/concorrenza (max 2) e transizioni di stato di `DownloadItem`.
- Sanitizzazione del nome file dal titolo.

**Integrazione / manuale (checklist di collaudo):**
- Video singolo standard → download ok.
- Playlist → espansione in più item + download in fila.
- Solo-audio (MP3) con copertina/metadati.
- URL rotto/privato → errore leggibile, coda prosegue.
- Bootstrap binari da zero (cartella vuota) e "Aggiorna yt-dlp".

---

## 9. Fuori ambito v1 (YAGNI)

- Sottotitoli.
- Login/cookie per contenuti privati.
- Editing/ritaglio/trim.
- Distribuzione a terzi, firma e notarizzazione.
- Ripristino della coda dopo la chiusura dell'app.
- Windows/Linux.

Tutte aggiungibili in seguito senza stravolgere l'architettura.

---

## 10. Rischi e note

- **Gatekeeper:** i binari scaricati non sono notarizzati; l'app rimuove la quarantena per eseguirli. Accettabile per uso personale.
- **Fragilità di yt-dlp:** i siti cambiano; l'aggiornamento facile di yt-dlp è la mitigazione principale.
- **Legalità/ToS:** strumento a uso personale; il rispetto dei termini delle piattaforme resta responsabilità dell'utente.
- **App non-sandboxed:** scelta consapevole per poter lanciare processi; nessuna distribuzione su App Store prevista.
