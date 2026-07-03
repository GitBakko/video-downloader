#!/usr/bin/env bash
#
# release.sh — cut a new Video Downloader release.
#
# Usage:
#   scripts/release.sh <version> [--skip-gates]
#   scripts/release.sh 1.1.0
#   scripts/release.sh 1.1.0-beta.1 --skip-gates
#
# It bumps the single source of truth (MARKETING_VERSION in App/project.yml),
# increments the build number, rolls CHANGELOG.md, runs the test/build gates,
# commits, and creates an annotated git tag vX.Y.Z. See docs/VERSIONING.md.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/App/project.yml"
CHANGELOG="$ROOT/CHANGELOG.md"

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
step() { printf '\n▸ %s\n' "$1"; }

# --- Parse args ---------------------------------------------------------------
VERSION="${1:-}"
SKIP_GATES=0
[ "${2:-}" = "--skip-gates" ] && SKIP_GATES=1
[ -n "$VERSION" ] || die "usage: scripts/release.sh <version> [--skip-gates]"

# Strip an optional leading 'v'.
VERSION="${VERSION#v}"

# SemVer (with optional pre-release / build metadata).
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then
  die "'$VERSION' is not valid SemVer (expected MAJOR.MINOR.PATCH[-prerelease])"
fi

# --- Preconditions ------------------------------------------------------------
command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"
[ "$(git -C "$ROOT" branch --show-current)" = "main" ] || die "must be on the 'main' branch"
[ -z "$(git -C "$ROOT" status --porcelain)" ] || die "working tree is not clean; commit or stash first"

CUR_VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION: "([^"]+)".*/\1/p' "$PROJECT" | head -1)"
[ -n "$CUR_VERSION" ] || die "could not read current MARKETING_VERSION from $PROJECT"
[ "$VERSION" != "$CUR_VERSION" ] || die "version $VERSION is already the current version"
# Warn (don't block) if the new version doesn't sort after the current one.
if [ "$(printf '%s\n%s\n' "$CUR_VERSION" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]; then
  printf 'warning: %s does not sort after current %s — continuing anyway\n' "$VERSION" "$CUR_VERSION" >&2
fi

CUR_BUILD="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' "$PROJECT" | head -1)"
[ -n "$CUR_BUILD" ] || die "could not read CURRENT_PROJECT_VERSION from $PROJECT"
NEW_BUILD=$((CUR_BUILD + 1))
DATE="$(date +%F)"

printf 'Releasing Video Downloader %s (build %s), was %s (build %s)\n' \
  "$VERSION" "$NEW_BUILD" "$CUR_VERSION" "$CUR_BUILD"

# --- 1. Bump version in project.yml ------------------------------------------
step "Updating App/project.yml"
sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION: )\"[^\"]*\"/\1\"$VERSION\"/" "$PROJECT"
sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION: )\"[0-9]+\"/\1\"$NEW_BUILD\"/" "$PROJECT"

# --- 2. Roll the changelog ----------------------------------------------------
step "Rolling CHANGELOG.md ([Unreleased] -> [$VERSION] - $DATE)"
grep -q '^## \[Unreleased\]' "$CHANGELOG" || die "no '## [Unreleased]' section in $CHANGELOG"
awk -v ver="$VERSION" -v date="$DATE" '
  !done && $0 == "## [Unreleased]" {
    print "## [Unreleased]"; print ""; print "_Nothing yet._"; print ""
    print "## [" ver "] - " date
    done = 1
    next
  }
  { print }
' "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"

# --- 3. Gates -----------------------------------------------------------------
if [ "$SKIP_GATES" -eq 1 ]; then
  printf '\n(skipping test/build gates by request)\n'
else
  step "Gate 1/2 — swift test"
  ( cd "$ROOT" && swift test )
  step "Gate 2/2 — xcodegen generate + xcodebuild"
  ( cd "$ROOT/App" && xcodegen generate >/dev/null )
  ( cd "$ROOT" && xcodebuild -project App/VideoDownloader.xcodeproj \
      -scheme VideoDownloader -configuration Debug \
      -destination 'platform=macOS' build >/dev/null )
  printf '  both gates passed\n'
fi

# --- 4. Commit + tag ----------------------------------------------------------
step "Committing and tagging v$VERSION"
git -C "$ROOT" add "$PROJECT" "$CHANGELOG"
git -C "$ROOT" commit -m "chore(release): v$VERSION"
git -C "$ROOT" tag -a "v$VERSION" -m "Video Downloader $VERSION"

printf '\n✓ Released v%s. Review with:\n    git show v%s\n' "$VERSION" "$VERSION"
printf '  If you have a remote:  git push && git push --tags\n'
