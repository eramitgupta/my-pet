#!/usr/bin/env bash
# End-to-end test of the update pipeline with the real Sparkle framework, fully offline:
#   throwaway EdDSA key → old build (0.0.0) + new build (current version) → signed update ZIP and
#   signed appcast (publish-update.sh) → local HTTP server → Sparkle finds, downloads, verifies,
#   installs. Then checks that a tampered download is rejected and the old app stays intact.
#   scripts/test-updates.sh
# It overwrites and then deletes build/MyPet.app (those builds carry the throwaway key).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FW="$ROOT/macos/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
WORK="$(mktemp -d)"; chmod 700 "$WORK"
PORT=8765
SERVER_PID=""
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null || true; fi
  rm -rf "$WORK"
  # These builds embed the throwaway key; never leave one behind where it could be shipped.
  rm -rf "$ROOT/build/MyPet.app" "$ROOT"/build/MyPet-*.zip
}
trap cleanup EXIT
fail() { echo "✗ $*" >&2; exit 1; }
quiet() { "$@" >"$WORK/step.log" 2>&1 || { cat "$WORK/step.log"; fail "$1 failed"; }; }
version_of() { /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$1/Contents/Info.plist"; }

echo "▸ Throwaway signing key"
swift "$ROOT/tests/update-harness/genkey.swift" "$WORK"
export MYPET_SPARKLE_PUBLIC_KEY="$(cat "$WORK/public.key")"
NEW="$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/Cargo.toml" | head -1)"
export MYPET_ARCHS="$(uname -m)"

echo "▸ Building the old version (0.0.0) and the new one ($NEW)"
MYPET_VERSION=0.0.0 quiet "$ROOT/scripts/build-app.sh" release
ditto "$ROOT/build/MyPet.app" "$WORK/old.app"
quiet "$ROOT/scripts/build-app.sh" release

echo "▸ Publishing a signed update to a local appcast"
mkdir -p "$WORK/www"
SPARKLE_PRIVATE_KEY="$(cat "$WORK/private.key")" \
  quiet "$ROOT/scripts/publish-update.sh" "$WORK/www/appcast.xml" "http://127.0.0.1:$PORT/"
cp "$ROOT/build/MyPet-$NEW.zip" "$WORK/www/"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/www" >/dev/null 2>&1 &
SERVER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -sf "http://127.0.0.1:$PORT/appcast.xml" >/dev/null && break; sleep 0.5; done

echo "▸ Building the Sparkle test harness"
swiftc -F "$FW" -framework Sparkle -Xlinker -rpath -Xlinker "$FW" \
  -o "$WORK/harness" "$ROOT/tests/update-harness/main.swift" 2>/dev/null
FEED="http://127.0.0.1:$PORT/appcast.xml"

echo "▸ Test 1: update is found, downloaded, verified and installed"
ditto "$WORK/old.app" "$WORK/install/MyPet.app"
"$WORK/harness" "$WORK/install/MyPet.app" "$FEED" install | sed 's/^/    /'
sleep 2
[[ "$(version_of "$WORK/install/MyPet.app")" == "$NEW" ]] || fail "installed version is $(version_of "$WORK/install/MyPet.app"), expected $NEW"
codesign --verify --strict --deep "$WORK/install/MyPet.app" || fail "updated app's code signature is invalid"
echo "  ✓ updated 0.0.0 → $NEW, signature valid"

echo "▸ Test 2: already up to date"
"$WORK/harness" "$WORK/install/MyPet.app" "$FEED" probe >/dev/null && fail "expected 'up to date'" || true
echo "  ✓ no update offered to $NEW"

echo "▸ Test 3: a tampered download is rejected and the old app is untouched"
rm -rf "$WORK/install/MyPet.app"; ditto "$WORK/old.app" "$WORK/install/MyPet.app"
python3 -c "import sys;p=sys.argv[1];b=bytearray(open(p,'rb').read());b[len(b)//2]^=0xFF;open(p,'wb').write(b)" "$WORK/www/MyPet-$NEW.zip"
if "$WORK/harness" "$WORK/install/MyPet.app" "$FEED" install >"$WORK/tamper.log" 2>&1; then fail "tampered update was accepted"; fi
grep -q "improperly signed" "$WORK/tamper.log" || { cat "$WORK/tamper.log"; fail "unexpected failure mode"; }
[[ "$(version_of "$WORK/install/MyPet.app")" == "0.0.0" ]] || fail "old app was modified"
echo "  ✓ rejected: $(grep -o 'The update is improperly signed[^.]*' "$WORK/tamper.log" | head -1)"

echo "✓ Update pipeline works end to end"
