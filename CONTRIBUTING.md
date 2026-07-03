# Contributing

Thanks for your interest! This is a small personal-use macOS app, but issues and PRs are
welcome.

## Project layout

- **`VideoDownloaderCore`** (`Sources/VideoDownloaderCore/`) — a dependency-free SwiftPM
  library with all the pure logic (models, parsing, argument building, download engine,
  queue/settings/history state). This is where most logic — and all unit tests — live.
- **App shell** (`App/`) — a thin SwiftUI layer. The Xcode project is **generated** by
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `App/project.yml`; the generated
  `App/VideoDownloader.xcodeproj` is gitignored — **never commit it**.

## The two gates

Every change must keep both green:

```bash
# Gate 1 — library tests (fast TDD loop)
swift test

# Gate 2 — the app builds
brew install xcodegen        # once
cd App && xcodegen generate
xcodebuild -project App/VideoDownloader.xcodeproj -scheme VideoDownloader \
  -configuration Debug -destination 'platform=macOS' build   # ** BUILD SUCCEEDED **
```

CI runs both on every push and pull request.

## Guidelines

- **TDD.** Prefer putting logic in `VideoDownloaderCore` with an XCTest, rather than in the
  SwiftUI views. Keep the app shell thin.
- **Small, focused commits** using [Conventional Commits](https://www.conventionalcommits.org)
  (`feat:`, `fix:`, `docs:`, `chore:` …).
- **Changelog.** User-facing changes go under `## [Unreleased]` in
  [`CHANGELOG.md`](CHANGELOG.md) (Keep a Changelog format).
- **UI strings are in Italian** to match the existing app.

## Cutting a release

Releases use [Semantic Versioning](https://semver.org). Maintainers cut one with:

```bash
scripts/release.sh X.Y.Z
```

which bumps the version, rolls the changelog, runs both gates, commits, and tags `vX.Y.Z`.
See [`docs/VERSIONING.md`](docs/VERSIONING.md).
