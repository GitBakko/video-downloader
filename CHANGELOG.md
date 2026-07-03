# Changelog

All notable changes to **Video Downloader** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
(see [`docs/VERSIONING.md`](docs/VERSIONING.md)).

## [Unreleased]

### Fixed
- **Clipboard capture no longer fires at startup.** The app now ignores whatever
  link is already on the clipboard when it launches and only proposes/auto-starts
  links copied *after* it's running (a baseline is taken at launch and only later
  changes count).

## [1.3.0] - 2026-07-03

### Added
- **In-app release history** (*Novità*): a window that shows this changelog
  parsed by version — what changed in each release, newest first, with the
  current version marked. Open it from the app menu (*Video Downloader → Novità…*)
  or the version link in the Help window. `CHANGELOG.md` is bundled into the app
  and rendered by a pure, tested parser (`ChangelogParser`).

## [1.2.0] - 2026-07-03

### Added
- **Download history** (*Cronologia*): a persistent, searchable log of completed
  downloads in its own window (View menu → *Cronologia download*, ⌘Y, or the
  toolbar clock button). Filter by source, title/URL search, and by *scaricato* /
  *aggiunto* date ranges; per-row *Rimetti in coda*, *Mostra nel Finder*, and
  *Rimuovi dalla cronologia*; plus *Svuota cronologia*. Stored at
  `~/Library/Application Support/VideoDownloader/history.json`.
- **Queue management**: remove a single video (right-click a row → *Rimuovi dalla
  coda*), and a *Coda* toolbar menu to *Rimuovi i completati*, *Rimuovi i terminati*,
  or *Svuota la coda*. Removing an active item stops its download first.
- **Auto-start toggle** (Settings → Download): when on, a link that's typed, pasted,
  or auto-detected from the clipboard starts downloading immediately — no manual
  *Scarica*.
- A floating **in-app toast** when a link is captured from the clipboard.
- **Configurable concurrency** (Settings → Download): how many downloads run at
  once overall *and* per source/site.

### Changed
- The **Help** and **first-launch setup** screens now show the real app icon.
- yt-dlp now uses an installed **JavaScript runtime** (deno/node/bun, resolved by
  absolute path) so YouTube extraction uses the proper web client — faster and more
  reliable than the deprecated fallback.
- A download that hasn't reported a percentage yet shows **"Preparazione"** (yt-dlp
  is still extracting the page/formats) instead of a stuck-looking "Scaricamento".

### Fixed
- The row's **"Formato"** section always shows the picker now (a `DisclosureGroup`
  nested inside a `List` could render empty).
- **Clipboard capture** is now reliable: the app polls the pasteboard on a timer,
  so a copied link is caught whether or not the app has focus (it used to check
  only when the app regained focus, so it "worked only sometimes").

## [1.1.0] - 2026-07-03

### Added
- **Source favicon** next to each video — the origin site's real favicon, cached
  on disk per host and deduplicated across concurrent lookups (a 30-item playlist
  fetches each site's icon only once).
- **Help window** (⌘? / Help menu) with a description of the app, how it works,
  popular-site chips, and a searchable list of all ~1800 sites yt-dlp supports.
- A pre-flight check of the download folder, with a clear message if it's missing
  or not writable (instead of a raw error mid-download).

### Changed
- **Much faster format detection.** yt-dlp now uses the *onedir* build instead of
  the self-extracting *onefile*, so each probe/download starts in **<1s** instead
  of ~24s (after a one-time first-run warm-up).
- **Snappier first launch** — component binaries download in parallel, and the
  one-time yt-dlp warm-up runs in the background so the window no longer freezes
  at 100%.
- **More native macOS UI** — the download queue is now a real `List`, window
  chrome moved into a proper toolbar, a compact first-launch setup window, and
  clearer primary/secondary buttons.
- Menu bar (and About) now read **"Video Downloader"**.

### Fixed
- Status dot **and** label now colour by state (were always grey).
- **Accessibility**: VoiceOver labels for the format pickers, the format table,
  status, and progress; decorative favicons/thumbnails/icons hidden; better
  contrast for the "queued" state.
- **Robustness**: a probing item can now be cancelled (and its yt-dlp process is
  killed); setup/update failures show a readable Italian message instead of
  "error 0"; "Aggiorna yt-dlp" no longer fails silently; an all-unavailable
  playlist reports it; re-adding a playlist no longer duplicates its videos; and
  in-flight downloads are stopped when you quit (no orphaned processes).
- The yt-dlp version in Settings now updates live once the warm-up finishes.
- Thumbnails are cached, so they no longer flash while scrolling the queue.

## [1.0.0] - 2026-07-03

First public version. A native macOS SwiftUI app that downloads video (or audio)
from almost any site — a curated GUI over `yt-dlp` + `ffmpeg`.

### Added

- **Download queue** — paste one or more URLs (or a whole playlist) and download
  them in a clean list; up to 2 downloads run in parallel, the rest queue.
- **Hybrid format selection** — simple presets (Video/Audio + quality) by default,
  with an expandable "tutti i formati" table for precise control; audio-only
  extraction to MP3.
- **Manual start & queue controls** — per-row *Scarica* and a global *Scarica tutti*,
  *Pausa/Riprendi coda*, per-item *Annulla* and *Riprova* (failed downloads never
  stop the queue).
- **Self-managed binaries** — on first launch the app downloads an architecture-matched
  `yt-dlp` + static `ffmpeg`/`ffprobe` into `~/Library/Application Support/VideoDownloader/bin`,
  with a real download-progress percentage, unquarantine + ad-hoc signing, and an
  *Aggiorna yt-dlp* action.
- **Output** — files saved to a fixed folder (default `~/Movies/VideoDownloader`,
  configurable) with an automatic, collision-safe filename; embedded thumbnail and
  metadata.
- **Convenience** — clipboard URL detection on launch/activation, completion
  notifications + sound with a *Mostra nel Finder* action, and a Settings window.
- **App icon** and a **`VideoDownloaderCore`** SwiftPM library with 87 unit tests.

### Known limitations

- Progress labels are state-based ("Scaricamento…" / "Elaborazione…"), not per-pass.
- Out of scope for 1.0.0: subtitles, login/cookies for private content, editing/trim,
  queue persistence across launches, notarized distribution, Windows/Linux.

<!--
Version-comparison links go here once a git remote exists, e.g.:
[Unreleased]: https://github.com/<owner>/VideoDownloader/compare/v1.0.0...HEAD
[1.0.0]:      https://github.com/<owner>/VideoDownloader/releases/tag/v1.0.0
Until then, browse history locally with `git log v1.0.0..HEAD`.
-->

