#!/usr/bin/env bash
#
# capture-screenshots.sh — grab a clean PNG of the Video Downloader window
# for the README, straight into docs/assets/screenshots/.
#
# Usage:
#   scripts/capture-screenshots.sh [name]     # default name: "main"
#
#   1. Build the app once (Release):
#        cd App && xcodegen generate && cd ..
#        xcodebuild -project App/VideoDownloader.xcodeproj -scheme VideoDownloader \
#          -configuration Release -destination 'platform=macOS' -derivedDataPath build build
#   2. Arrange the app window the way you want it (add a URL, open Settings, …).
#   3. Run this. It captures the FRONTMOST Video Downloader window.
#
# Requires Screen Recording permission for the terminal you run it from
# (macOS will prompt once; grant it in System Settings › Privacy & Security ›
# Screen Recording, then re-run).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${1:-main}"
OUT_DIR="$ROOT/docs/assets/screenshots"
OUT="$OUT_DIR/$NAME.png"
APP="$ROOT/build/Build/Products/Release/Video Downloader.app"
mkdir -p "$OUT_DIR"

# Launch the built app if it isn't already running.
if ! pgrep -x "Video Downloader" >/dev/null 2>&1; then
  [ -d "$APP" ] || { echo "error: build the Release app first (see header comment): $APP" >&2; exit 1; }
  open "$APP"
fi

# Find the window id of the frontmost normal window owned by the app.
win_id() {
  swift - "Video Downloader" <<'SWIFT'
import CoreGraphics
import Foundation
let name = CommandLine.arguments.dropFirst().first ?? ""
guard let list = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
else { exit(1) }
for w in list where (w[kCGWindowOwnerName as String] as? String) == name
    && (w[kCGWindowLayer as String] as? Int) == 0 {
    if let n = w[kCGWindowNumber as String] as? Int,
       let b = w[kCGWindowBounds as String] as? [String: CGFloat],
       (b["Width"] ?? 0) > 200, (b["Height"] ?? 0) > 200 {
        print(n); exit(0)
    }
}
exit(2)
SWIFT
}

ID=""
for _ in $(seq 1 20); do
  if ID=$(win_id 2>/dev/null); then break; fi
  sleep 0.5
done
[ -n "$ID" ] || { echo "error: could not find a Video Downloader window" >&2; exit 1; }

# -o drops the drop-shadow, -x silences the shutter sound.
screencapture -o -x -l"$ID" "$OUT"
echo "saved $OUT"
