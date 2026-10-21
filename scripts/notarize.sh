#!/usr/bin/env bash
# Signs mypet with a Developer ID, notarises the DMG with Apple and staples the ticket.
#
# Required:
#   MYPET_SIGN_IDENTITY   e.g. "Developer ID Application: Jane Doe (ABCDE12345)"
# Plus ONE of:
#   MYPET_NOTARY_PROFILE  a keychain profile created with
#                          `xcrun notarytool store-credentials <name> --apple-id … --team-id …`
#   APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD   (app-specific password from appleid.apple.com)
#
# Requires full Xcode (notarytool and stapler are not in the Command Line Tools on all versions).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
die() { echo "error: $*" >&2; exit 1; }

[[ -n "${MYPET_SIGN_IDENTITY:-}" && "$MYPET_SIGN_IDENTITY" != "-" ]] ||
  die "MYPET_SIGN_IDENTITY is not set. Local builds don't need notarisation; see README → Distribution."
security find-identity -v -p codesigning | grep -q "$MYPET_SIGN_IDENTITY" ||
  die "signing identity \"$MYPET_SIGN_IDENTITY\" not found in your keychain"

if [[ -n "${MYPET_NOTARY_PROFILE:-}" ]]; then
  AUTH=(--keychain-profile "$MYPET_NOTARY_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
  die "set MYPET_NOTARY_PROFILE, or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD"
fi
xcrun --find notarytool >/dev/null 2>&1 || die "notarytool not found — install full Xcode"

# build-app.sh signs the app and Sparkle's helpers with hardened runtime + secure timestamp.
"$ROOT/scripts/build-app.sh" release
APP="$ROOT/build/MyPet.app"

# 1. Notarise and staple the app itself. The Sparkle update archive (publish-update.sh) is made
#    from this stapled app, so updated copies pass Gatekeeper offline too.
SUBMIT="$(mktemp -d)/mypet.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT"
echo "▸ Notarising the app (this usually takes a few minutes)"
xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute -v "$APP"

# 2. Package the stapled app in a DMG for first-time installs, then notarise that too.
"$ROOT/scripts/make-dmg.sh"
DMG="$(ls -t "$ROOT"/build/MyPet-*.dmg | head -1)"
echo "▸ Notarising $DMG"
xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "✓ Notarised: $APP and $DMG"
