#!/usr/bin/env bash
# Packages build/MyPet.app as a Sparkle update and adds it to the signed appcast.
#   scripts/publish-update.sh <appcast.xml> <download-url-prefix>
# Example (what the release workflow runs):
#   scripts/publish-update.sh pages/appcast.xml https://github.com/eramitgupta/my-pet/releases/download/v0.2.0/
#
# Signing key: SPARKLE_PRIVATE_KEY (the exported EdDSA private key, e.g. a GitHub secret) is
# piped to sign_update on stdin and never touches disk. Without it, sign_update uses the
# key in your login Keychain (created by scripts/sparkle-keys.sh).
#
# Output: build/MyPet-<version>.zip (the update archive) and an updated, signed appcast.
set -euo pipefail

APPCAST="${1:?usage: publish-update.sh <appcast.xml> <download-url-prefix>}"
PREFIX="${2:?usage: publish-update.sh <appcast.xml> <download-url-prefix>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MyPet.app"
BIN="$ROOT/macos/.build/artifacts/sparkle/Sparkle/bin"
[[ -d "$APP" ]] || { echo "error: $APP not found; build it first" >&2; exit 1; }
[[ -x "$BIN/sign_update" ]] || { echo "error: Sparkle tools missing; run: swift package --package-path macos resolve" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
KEY_IN_APP="$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ -n "$KEY_IN_APP" ]] || { echo "error: the app has no SUPublicEDKey; it could never verify this update (see docs/UPDATES.md)" >&2; exit 1; }

sign() { # sign_update with the secret from the environment (stdin) or the Keychain
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$BIN/sign_update" --ed-key-file - "$@"
  else
    "$BIN/sign_update" "$@"
  fi
}

ZIP="$ROOT/build/MyPet-$VERSION.zip"
echo "▸ Archiving $APP → $ZIP"
rm -f "$ZIP"
# ditto keeps symlinks, permissions and code signatures intact (plain zip would break them).
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "▸ Signing the archive (EdDSA)"
ENCLOSURE="$(sign "$ZIP")"

echo "▸ Updating $APPCAST"
python3 "$ROOT/scripts/update-appcast.py" --appcast "$APPCAST" --version "$VERSION" \
  --url "${PREFIX%/}/MyPet-$VERSION.zip" --enclosure "$ENCLOSURE" ${MYPET_CHANGELOG:+--changelog "$MYPET_CHANGELOG"}

echo "▸ Signing the appcast feed"
sign "$APPCAST"

# Check the archive against the key *inside the app*, as Sparkle will on users' Macs, so a
# key mix-up fails here instead of breaking everyone's updates.
SIG="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$ENCLOSURE")"
swift "$ROOT/scripts/verify-update.swift" "$ZIP" "$SIG" "$APP"
echo "✓ $VERSION ready: upload $(basename "$ZIP") to the release, publish $(basename "$APPCAST")"
