#!/usr/bin/env bash
# Packages build/MyPet.app into build/MyPet-<version>.dmg (drag-to-Applications layout).
#   scripts/make-dmg.sh            # uses an existing build/MyPet.app
#   scripts/make-dmg.sh --build    # runs scripts/build-app.sh release first
# If MYPET_SIGN_IDENTITY is set, the DMG is signed too (needed before notarisation).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MyPet.app"
[[ "${1:-}" == "--build" ]] && "$ROOT/scripts/build-app.sh" release
[[ -d "$APP" ]] || { echo "error: $APP not found — run scripts/build-app.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/MyPet-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "MyPet $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

if [[ -n "${MYPET_SIGN_IDENTITY:-}" && "${MYPET_SIGN_IDENTITY}" != "-" ]]; then
  codesign --force --sign "$MYPET_SIGN_IDENTITY" --timestamp "$DMG"
fi
hdiutil verify "$DMG" >/dev/null
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
