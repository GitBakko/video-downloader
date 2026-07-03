# Changelog

All notable changes to **Video Downloader** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
(see [`docs/VERSIONING.md`](docs/VERSIONING.md)).

## [Unreleased]

_Nothing yet._

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

