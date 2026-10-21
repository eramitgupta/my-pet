#!/usr/bin/env bash
# Builds MyPet.app with SwiftPM — works with only the Xcode Command Line Tools.
#   scripts/build-app.sh [debug|release]      → build/MyPet.app
# Environment:
#   MYPET_ARCHS="arm64 x86_64"   architectures (default: universal for release, native for debug)
#   MYPET_SIGN_IDENTITY="Developer ID Application: …"   (default "-" = ad-hoc, no account needed)
#   MYPET_VERSION=1.2.3          override the version from Cargo.toml (used for update testing)
#   MYPET_SPARKLE_PUBLIC_KEY=…   override SPARKLE_PUBLIC_KEY from macos/project.yml (testing)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MACOS="$ROOT/macos"
OUT="$ROOT/build"
APP="$OUT/MyPet.app"
# One version everywhere. Sparkle compares CFBundleVersion, so it must equal the release
# version and grow with every release (a timestamp would differ between CI and local builds).
VERSION="${MYPET_VERSION:-$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/Cargo.toml" | head -1)}"
IDENTITY="${MYPET_SIGN_IDENTITY:--}"

setting() { # build setting from macos/project.yml (the single source shared with Xcode)
  sed -n "s/^ *$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\} *$/\1/p" "$MACOS/project.yml" | head -1
}
SPARKLE_PUBLIC_KEY="${MYPET_SPARKLE_PUBLIC_KEY:-$(setting SPARKLE_PUBLIC_KEY)}"
SPARKLE_FEED_URL="$(setting SPARKLE_FEED_URL)"

if [[ -z "${MYPET_ARCHS:-}" ]]; then
  if [[ "$CONFIG" == "release" ]]; then MYPET_ARCHS="arm64 x86_64"; else MYPET_ARCHS="$(uname -m)"; fi
fi

echo "▸ Rust core ($CONFIG)"
"$ROOT/scripts/build-rust.sh" "$CONFIG"

echo "▸ Swift app ($CONFIG; $MYPET_ARCHS)"
export MYPET_RUST_CONFIG="$CONFIG"
# Sparkle is public: never let git's Keychain credential helper pop up a password prompt.
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
SWIFT_FLAGS=(--package-path "$MACOS" -c "$CONFIG" --only-use-versions-from-resolved-file)
BINS=()
STAGE="$OUT/.stage"
mkdir -p "$STAGE"
for arch in $MYPET_ARCHS; do
  BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --arch "$arch" --show-bin-path)"
  # SwiftPM doesn't track libpet_core.a as an input; remove the old binary so a Rust-only
  # change is always relinked.
  rm -f "$BIN_DIR/mypet"
  swift build "${SWIFT_FLAGS[@]}" --arch "$arch" --product mypet
  # The bin path is shared between architectures, so copy each slice out before the next build.
  cp "$BIN_DIR/mypet" "$STAGE/MyPet-$arch"
  BINS+=("$STAGE/MyPet-$arch")
done

echo "▸ Assembling $APP (version $VERSION)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
if [[ ${#BINS[@]} -gt 1 ]]; then
  lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/MyPet"
else
  cp "${BINS[0]}" "$APP/Contents/MacOS/MyPet"
fi

# Resolve the Xcode-style build variables in Info.plist.
sed -e "s/\$(EXECUTABLE_NAME)/MyPet/" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.erag.mypet/" \
    -e "s/\$(MARKETING_VERSION)/$VERSION/" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$VERSION/" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/13.0/" \
    -e "s#\$(SPARKLE_FEED_URL)#$SPARKLE_FEED_URL#" \
    -e "s#\$(SPARKLE_PUBLIC_KEY)#$SPARKLE_PUBLIC_KEY#" \
    "$MACOS/mypet/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
[[ -n "$SPARKLE_PUBLIC_KEY" ]] || echo "  note: no SPARKLE_PUBLIC_KEY, so this build can't update itself (see docs/UPDATES.md)"

rsync -a --delete --exclude '.DS_Store' "$MACOS/mypet/Assets/Pets/" "$APP/Contents/Resources/Pets/"
cp "$MACOS/mypet/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Sparkle.framework from the resolved SwiftPM artifact. ditto keeps its symlinks intact.
SPARKLE_FW="$MACOS/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE_FW" ]] || { echo "error: Sparkle.framework not found; run: swift package --package-path macos resolve" >&2; exit 1; }
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"

echo "▸ Signing ($([[ "$IDENTITY" == "-" ]] && echo ad-hoc || echo "$IDENTITY"))"
SIGN=(codesign --force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then
  SIGN+=(--options runtime --timestamp)
fi
# Sparkle's documented order: its helpers inside-out, then the framework, then the app.
# The Downloader XPC service keeps its own entitlements.
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
"${SIGN[@]}" "$FW/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$FW/Autoupdate"
"${SIGN[@]}" "$FW/Updater.app"
"${SIGN[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" --entitlements "$MACOS/mypet/mypet.entitlements" "$APP"
codesign --verify --strict --deep "$APP"

echo "✓ $APP ($(lipo -archs "$APP/Contents/MacOS/MyPet"), $(du -sh "$APP" | cut -f1))"
