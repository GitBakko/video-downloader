# Video Downloader per macOS — Documento di Design

**Data:** 2026-07-01
**Stato:** Approvato in brainstorming, revisionato (review multi-agente), pronto per il piano di implementazione
**Autore:** bakko (con Claude)

---

## 1. Obiettivo

Un'app **macOS nativa in SwiftUI**, con una singola finestra, che permette di scaricare video (o solo l'audio) da un URL incollato, da praticamente qualunque piattaforma. L'utente incolla uno o più URL (anche playlist), l'app legge i formati disponibili, l'utente conferma *come* scaricare e premendo Scarica l'app scarica i file in una cartella.

L'app è un'**interfaccia curata sopra `yt-dlp` + `ffmpeg`**: sono questi due strumenti open-source a fare il lavoro di estrazione, download, unione e conversione. Non si tenta di reimplementare in Swift la logica di estrazione dai singoli siti (irrealistico e fragile).

**Uso:** personale (solo l'autore). Nessuna distribuzione a terzi in v1, quindi nessuna notarizzazione Apple. L'app userà comunque una **firma ad-hoc** (l'impostazione di default di Xcode) — vedi §10.

**Filosofia:** "semplice semplice". Copre benissimo il caso comune, senza tagliare fuori il controllo fine quando serve.

---

## 2. Decisioni chiave (esito del brainstorming + review)

| # | Decisione | Scelta |
|---|-----------|--------|
| 1 | Motore di download | Wrapper nativo su **yt-dlp + ffmpeg** |
| 2 | Destinatario | **Solo uso personale** (no notarizzazione/distribuzione) |
| 3 | Gestione dei binari | L'app **si auto-gestisce** yt-dlp e ffmpeg (+ffprobe): li scarica al primo avvio per l'**architettura giusta** del Mac, li tiene in una sua cartella, offre "Aggiorna yt-dlp" |
| 4 | Scelta del formato | **Ibrida**: preset semplici (Video/Audio + qualità) di default, con "mostra tutti i formati" (tabella completa) a richiesta |
| 5 | Ambito | **Coda** ordinata con supporto **playlist** (una playlist si espande in tanti item con un unico probe) |
| 6 | Layout finestra | **Formato di default in alto + lista** dei download; ogni riga espandibile per override del formato |
| 7 | **Avvio del download** | **Manuale**: dopo il probe l'item resta `ready`; parte con "Scarica" per riga o "Scarica tutti". Rispetta il tetto di 2 in parallelo |
| 8 | Salvataggio | **Cartella fissa** con **nome automatico** dal titolo (+id per unicità); cartella modificabile nelle impostazioni |
| 9 | Extra inclusi | **Rileva URL dagli appunti**, **notifica+suono a fine download** (+ "Mostra nel Finder"), **incorpora copertina/metadati** |
| 10 | Extra esclusi | Sottotitoli (fuori dalla v1) |
| 11 | Requisiti | **macOS 14+**, app **non-sandboxed**, **max 2 download in parallelo** |

---

## 3. Architettura

App **non sandboxed** (necessario per lanciare processi esterni e usare la rete senza restrizioni del sandbox), SwiftUI, target **macOS 14+**, struttura MVVM leggera. Cinque componenti con responsabilità nette + le View.

### 3.1 `BinaryManager`
**Cosa fa:** garantisce che yt-dlp, ffmpeg e ffprobe siano presenti ed eseguibili.
- Cartella gestita: `~/Library/Application Support/VideoDownloader/bin/`.
- Al primo avvio (o se mancanti): scarica l'ultima build standalone di **yt-dlp** (`yt-dlp_macos` dalle GitHub Releases del progetto) e una build **statica di ffmpeg + ffprobe** scelta in base all'**architettura del Mac** (host `arm64` vs `x86_64`). Nota: non esiste una build statica ufficiale di ffmpeg per macOS → si punta a una sorgente affidabile arch-specifica (es. build arm64 dedicate per Apple Silicon; evermeet.cx è x86_64/Rosetta). `ffprobe` va incluso perché yt-dlp lo raccomanda fortemente (senza, l'estrazione MP3 e i metadati risultano degradati).
- Dopo il download: rimuove l'attributo di **quarantena Gatekeeper** (`com.apple.quarantine`) e imposta il bit di esecuzione. Fallback: se un binario `arm64` non è già firmato ad-hoc, applica `codesign -s - <binario>` (il kernel altrimenti fa SIGKILL dei binari arm64 non firmati). La firma ad-hoc è distinta e compatibile con la scelta di non notarizzare.
- Espone: percorso di yt-dlp, cartella di ffmpeg/ffprobe (per `--ffmpeg-location`), versione corrente di yt-dlp, azione **"Aggiorna yt-dlp"**.
- **Dipende da:** rete, filesystem.

### 3.2 `MediaProbe`
**Cosa fa:** dato un URL, ne ricava i metadati e la lista formati **senza scaricare**.
- Esegue un **unico** `yt-dlp -J --no-warnings <url>` (dump JSON completo). Per una **playlist**, questo singolo processo restituisce le `entries` con titolo/miniatura/formati di ogni video → si **espandono** in più `DownloadItem`, tutti in stato `ready`. Nessuno stato intermedio, **concorrenza di probe = 1** (un solo `-J` per operazione di aggiunta, niente 100 processi paralleli).
- Ricava per ciascun item: titolo, durata, URL miniatura, ed elenco `formats` (risoluzione, ext, vcodec, acodec, filesize/approx, tbr, note).
- Limite noto: per playlist molto grandi il `-J` completo può essere lento (estrae i formati di tutti i video); accettabile in v1, il probe "lazy" resta un possibile miglioramento futuro.
- **Dipende da:** `BinaryManager` (percorso yt-dlp), rete.

### 3.3 `DownloadEngine`
**Cosa fa:** esegue i download e riporta l'avanzamento.
- Per ogni item avviato lancia `yt-dlp` come **`Process`** con gli argomenti costruiti (vedi §6).
- Cattura **contemporaneamente stdout e stderr** con due `readabilityHandler`: stdout per le righe del `--progress-template`, stderr per la mappatura errori (§7). Tutti gli aggiornamenti sono **marshallati sul main actor** prima di mutare lo `QueueStore` osservabile.
- Gestisce la **coda** con concorrenza **massima 2** in download: gli item avviati oltre il tetto restano `queued`.
- Passa a yt-dlp: formato scelto, cartella+template di nome, `--ffmpeg-location`, flag per copertina/metadati.
- Supporta **annulla** (termina il processo dell'item) e **pausa coda** globale, senza toccare gli item già in corso in modo distruttivo.
- **Dipende da:** `BinaryManager`, `MediaProbe` (formati), filesystem.

### 3.4 `QueueStore` (ViewModel osservabile)
**Cosa fa:** sorgente di verità della UI.
- `@Observable` con l'array di `DownloadItem`.
- Coordina: probe → `ready` → (utente preme Scarica) → `queued`/`downloading` → `processing` → `completed`/`failed`/`cancelled`.
- Applica il **formato di default** ai nuovi item; consente **override per-item finché l'item è `ready` o `queued`** (non ancora partito).
- Azioni: "Scarica" (per riga), "Scarica tutti", "Pausa/Riprendi coda", "Annulla" (per riga), "Riprova".
- **Dipende da:** `MediaProbe`, `DownloadEngine`, `SettingsStore`.

### 3.5 `SettingsStore`
**Cosa fa:** preferenze persistenti minime (UserDefaults).
- Cartella di destinazione (default `~/Movies/VideoDownloader`), formato di default (Video/Audio + qualità), toggle degli extra.
- **Dipende da:** UserDefaults.

### 3.6 View (SwiftUI)
- `MainWindowView`: barra di aggiunta URL + barra formato di default + destinazione + "Scarica tutti"/"Pausa coda", e la **lista** dei download.
- `DownloadRowView`: riga con miniatura, titolo, stato/progresso, **pulsante "Scarica"** (se `ready`), azioni; espandibile per il **selettore ibrido** dei formati (attivo finché `ready`/`queued`).
- `FormatPickerView`: preset (Video/Audio, qualità) + disclosure "tutti i formati" con tabella.
- `SetupView`: schermata mostrata se i binari mancano o il loro download fallisce.
- `SettingsView`: cartella, formato di default, extra.
- **Appunti:** all'avvio e a ogni **riattivazione** dell'app (macOS non ha un evento di cambio pasteboard), se `NSPasteboard` contiene un URL, l'app lo **propone** nel campo — senza sovrascrivere testo già digitato dall'utente e senza riproporre un URL già aggiunto alla lista.

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
├─ selectedFormat: FormatChoice   // default o override; editabile finché ready/queued
├─ state: DownloadState
├─ stage: String?            // etichetta fase corrente ("Scarico video", "Unione…")
├─ progress: Double?          // 0…1, nil quando indeterminato (processing)
├─ speed: String?            // es. "4.2 MB/s"
├─ eta: String?             // es. "0:38"
├─ outputPath: URL?
└─ errorMessage: String?

DownloadState = enum {
  probing,       // lettura formati in corso
  ready,         // formati letti, in attesa che l'utente prema Scarica
  queued,        // avviato dall'utente ma in attesa di uno slot (max 2)
  downloading,   // yt-dlp sta scaricando gli stream
  processing,    // post-processing (unione/rimux/embed/estrazione mp3): progresso indeterminato
  completed,
  failed,
  cancelled
}

MediaFormat
├─ formatID: String
├─ resolution: String?        // "1080p"
├─ ext: String              // "mp4", "m4a", "webm"
├─ vcodec: String?           // "H.264", "VP9", "none"
├─ acodec: String?           // "aac", "opus", "none"  ← usato per decidere se aggiungere audio
├─ filesize: Int64?          // byte, esatta o approssimata
└─ note: String?

FormatChoice = enum {
  case video(quality: VideoQuality)   // best | p1080 | p720 | p480
  case audio(quality: AudioQuality)   // v1: best  (→ MP3)
  case specific(formatID: String)
}
```

**Assi separati:** video e audio hanno **qualità distinte** (niente più `.preset(audioOnly, p720)` senza senso). In v1 l'audio è sempre **MP3 best**; l'enum `AudioQuality` resta estendibile (es. 192/128 kbps) in futuro.

**Progresso multi-stream:** un download `bv*+ba` fa due passate 0→100% (prima video, poi audio); il post-processing (unione/embed/estrazione) non emette percentuali. Per evitare che la barra "torni a 0" o si blocchi al 100%: durante `downloading` la barra riflette la passata corrente con l'etichetta `stage` ("Scarico video/audio"); all'inizio del post-processing l'item passa a `processing` con indicatore **indeterminato**.

**Persistenza:** la coda vive **in memoria** durante la sessione (nessun ripristino dopo la chiusura in v1). Solo le **impostazioni** (cartella, formato di default, extra) sono persistite in UserDefaults.

---

## 5. Flussi

### 5.1 Primo avvio / bootstrap binari
1. `BinaryManager` verifica la presenza di yt-dlp, ffmpeg e ffprobe.
2. Se mancano → `SetupView` con progresso di download; al termine: rimozione quarantena, bit di esecuzione, e (se serve) firma ad-hoc dei binari arm64.
3. Se il download fallisce → messaggio chiaro + "Riprova".

### 5.2 Aggiunta e download
1. L'utente incolla un URL (o l'app lo **propone dagli appunti** all'avvio/riattivazione, senza sovrascrivere testo digitato) → *Aggiungi*.
2. `MediaProbe` esegue un unico `yt-dlp -J` → l'item (o, per playlist, **tutti** gli item) compare in stato `ready` con titolo e miniatura.
3. Vale il **formato di default**; finché l'item è `ready`/`queued` l'utente può espandere la riga e scegliere un preset diverso o un formato specifico (modalità ibrida).
4. L'utente preme **"Scarica"** sulla riga (o **"Scarica tutti"**). L'item va `queued` e poi `downloading` appena c'è uno slot libero (tetto **2 in parallelo**). Barra, `stage`, velocità, ETA in riga; poi `processing` per l'unione/embed.
5. A fine: **notifica + suono**, copertina/metadati incorporati (se attivo), "Mostra nel Finder". File in `<cartella>/<titolo> [<id>].<ext>`.

### 5.3 Aggiornamento di yt-dlp
- Pulsante "Aggiorna yt-dlp" → `BinaryManager` riscarica l'ultima versione e aggiorna l'indicatore di versione.

---

## 6. Interfaccia con yt-dlp (dettagli concreti)

**Probe formati (nessun download), anche per playlist:**
```
yt-dlp -J --no-warnings <url>
```

**Costruzione del `-f` da `FormatChoice`:**

- `.video(best)` → `-f "bv*+ba/b"` con `--merge-output-format mp4` **e** `--remux-video mp4` (il fallback `b` può essere un contenitore già muxato non-mp4: il remux garantisce l'MP4 promesso dalla UI).
- `.video(p1080|p720|p480)` → `-f "bv*[height<=N]+ba/b[height<=N]"` + `--merge-output-format mp4` + `--remux-video mp4`.
- `.audio(best)` → `-f "ba/b" -x --audio-format mp3`.
- `.specific(formatID)`:
  - se il `MediaFormat` scelto ha `acodec == "none"` (solo-video) → `-f "<formatID>+bestaudio"` + `--merge-output-format mp4` + `--remux-video mp4` (così **non escono mai file muti**);
  - altrimenti → `-f "<formatID>"`.

**Flag comuni:**
```
--ffmpeg-location <bin_dir>
--embed-thumbnail --embed-metadata            # se l'extra è attivo
-o "<cartella>/%(title)s [%(id)s].%(ext)s"    # %(id)s garantisce unicità → niente sovrascritture
--newline
--progress-template "download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"
```

Il nome file è prodotto dal **template `-o` di yt-dlp** (che sanitizza da sé); non c'è sanitizzazione lato Swift. L'inclusione di `%(id)s` evita collisioni tra due video con lo stesso titolo (tipico nelle playlist).

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
| ffmpeg/ffprobe mancante per unione/estrazione | Rilevato prima dell'avvio, non a metà download |

Lo stderr e l'exit-code di yt-dlp vengono mappati a messaggi umani per i casi più comuni; per gli altri si mostra l'ultima riga significativa di stderr.

---

## 8. Strategia di test

**Unit (senza rete, veloci e affidabili):**
- Parsing del JSON di yt-dlp → `[MediaFormat]` e (per playlist) `[DownloadItem]`, su fixture reali salvate (video singolo, playlist, solo-audio).
- Parsing delle righe di `--progress-template` → percentuale/velocità/ETA, incluse le **due passate** video+audio.
- **Costruzione degli argomenti** da `FormatChoice` + impostazioni → array corretto per tutti i casi (`.video` a varie qualità, `.audio`, `.specific` con e senza audio da aggiungere; presenza di `--remux-video`/`--merge-output-format`).
- Verifica del **template `-o`** passato a yt-dlp (inclusione di `%(id)s` per l'unicità) — non una sanitizzazione lato Swift.
- Logica di coda/concorrenza (max 2), transizioni di stato di `DownloadItem` (inclusi `queued` e `processing`) e regola "override consentito solo finché ready/queued".

**Integrazione / manuale (checklist di collaudo):**
- Video singolo standard → download + remux MP4 ok.
- Playlist → un solo probe espande in più item + download in fila (max 2).
- Solo-audio (MP3) con copertina/metadati (verifica che ffprobe sia presente).
- Formato "solo-video" dalla tabella → esce con audio, non muto.
- URL rotto/privato → errore leggibile, coda prosegue.
- Bootstrap binari da zero (cartella vuota), su Apple Silicon (firma ad-hoc) e "Aggiorna yt-dlp".

---

## 9. Fuori ambito v1 (YAGNI)

- Sottotitoli.
- Login/cookie per contenuti privati.
- Editing/ritaglio/trim.
- Distribuzione a terzi e notarizzazione Apple.
- Ripristino della coda dopo la chiusura dell'app.
- Probe "lazy" delle playlist (le playlist enormi in v1 fanno un probe completo iniziale).
- Windows/Linux.

Tutte aggiungibili in seguito senza stravolgere l'architettura.

---

## 10. Rischi e note

- **Gatekeeper & firma:** i binari scaricati non sono notarizzati; l'app rimuove la quarantena e applica una firma **ad-hoc** ai binari arm64 non firmati (il kernel altrimenti li termina). L'app stessa resta firmata ad-hoc con un **bundle id stabile** (default di Xcode): serve perché `UNUserNotificationCenter` (notifiche a fine download) non funziona da un processo non firmato. La firma ad-hoc è indipendente dalla notarizzazione, che resta fuori ambito.
- **ffmpeg su macOS:** nessuna build statica ufficiale → si dipende da una sorgente terza affidabile, scelta per architettura, con `ffprobe` incluso.
- **Fragilità di yt-dlp:** i siti cambiano; l'aggiornamento facile di yt-dlp è la mitigazione principale.
- **Legalità/ToS:** strumento a uso personale; il rispetto dei termini delle piattaforme resta responsabilità dell'utente.
- **App non-sandboxed:** scelta consapevole per poter lanciare processi; nessuna distribuzione su App Store prevista.
