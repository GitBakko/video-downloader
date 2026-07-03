# Versioning & release process

Video Downloader follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html):
**`MAJOR.MINOR.PATCH`**.

| Bump | When |
|------|------|
| **MAJOR** | Incompatible change to how the app is used or configured (e.g. dropping a supported macOS version, removing/redesigning a core workflow). |
| **MINOR** | New, backwards-compatible functionality (e.g. subtitle support, a new format option, queue persistence). |
| **PATCH** | Backwards-compatible bug fixes and internal changes (e.g. the notification-bootstrap fix, a parsing fix). |

Pre-releases use a suffix: `1.1.0-beta.1`.

## Single source of truth

The version lives in **one place**: `MARKETING_VERSION` in `App/project.yml`.

- `App/Info.plist` maps it to the bundle automatically:
  - `CFBundleShortVersionString` = `$(MARKETING_VERSION)` — the user-facing version (About panel, Settings).
  - `CFBundleVersion` = `$(CURRENT_PROJECT_VERSION)` — a monotonically increasing **build number** (an integer; not the SemVer string).
- `CHANGELOG.md` records what changed in each version (see below).
- A git tag `vX.Y.Z` marks the exact released commit.

The display name is **"Video Downloader"** (`CFBundleDisplayName`); the product/bundle
name stays `VideoDownloader` and the bundle id `com.bakko.VideoDownloader` — those are
identifiers and never change casually.

The library (`VideoDownloaderCore`) is versioned together with the app; it is not
published as a standalone SwiftPM product.

## Changelog

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
During development, add entries under the top **`## [Unreleased]`** section, grouped
as `Added` / `Changed` / `Fixed` / `Removed` / `Deprecated` / `Security`. Cutting a
release turns `[Unreleased]` into `[X.Y.Z] - <date>` and starts a fresh empty
`[Unreleased]`.

## Cutting a release

Use the helper (it does everything below in the right order):

```bash
scripts/release.sh 1.1.0            # or: scripts/release.sh 1.1.0-beta.1
```

It will:

1. Validate the version is well-formed SemVer and greater than the current one.
2. Verify the working tree is clean and you're on `main`.
3. Set `MARKETING_VERSION` and bump `CURRENT_PROJECT_VERSION` in `App/project.yml`.
4. Roll `CHANGELOG.md`: `[Unreleased]` → `[X.Y.Z] - <today>`, new empty `[Unreleased]`.
5. Run both gates: `swift test` and an app `xcodebuild` (unless `--skip-gates`).
6. Commit `chore(release): vX.Y.Z` and create the annotated tag `vX.Y.Z`.

Then browse or share the release:

```bash
git show v1.1.0            # the release commit + tag
git log v1.0.0..v1.1.0     # everything since the previous release
```

If/when a git remote is added: `git push && git push --tags`, and fill in the
compare links at the bottom of `CHANGELOG.md`.

## Doing it by hand (if you skip the script)

1. Edit `MARKETING_VERSION` in `App/project.yml`; bump `CURRENT_PROJECT_VERSION`.
2. Update `CHANGELOG.md` (`[Unreleased]` → `[X.Y.Z] - <date>`, add a new `[Unreleased]`).
3. `cd App && xcodegen generate` and confirm the app builds; run `swift test`.
4. `git commit -am "chore(release): vX.Y.Z"`.
5. `git tag -a vX.Y.Z -m "Video Downloader X.Y.Z"`.
