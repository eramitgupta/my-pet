#!/usr/bin/env bash
# Builds libpet_core.a for arm64 and x86_64 and merges them into a universal library.
#   scripts/build-rust.sh [debug|release]
# Output: target/universal/<config>/libpet_core.a
set -euo pipefail

CONFIG="${1:-${CONFIGURATION:-debug}}"
CONFIG="$(echo "$CONFIG" | tr '[:upper:]' '[:lower:]')"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Xcode build phases run with a minimal PATH; find cargo the usual ways.
for dir in "$HOME/.cargo/bin" /opt/homebrew/opt/rustup/bin /usr/local/opt/rustup/bin /opt/homebrew/bin /usr/local/bin; do
  [[ -d "$dir" ]] && PATH="$dir:$PATH"
done
command -v cargo >/dev/null || { echo "error: cargo not found. Install Rust: https://rustup.rs" >&2; exit 1; }

# Xcode exports SDKROOT etc. for the app's own target; let cargo pick its own toolchain env.
unset SDKROOT IPHONEOS_DEPLOYMENT_TARGET
export MACOSX_DEPLOYMENT_TARGET=13.0

PROFILE_FLAG=()
[[ "$CONFIG" == "release" ]] && PROFILE_FLAG=(--release)

TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)
if command -v rustup >/dev/null; then
  installed="$(rustup target list --installed)"
  for t in "${TARGETS[@]}"; do
    grep -qx "$t" <<<"$installed" || rustup target add "$t"
  done
fi

LIBS=()
for t in "${TARGETS[@]}"; do
  cargo build --manifest-path "$ROOT/Cargo.toml" -p pet-core --lib --target "$t" ${PROFILE_FLAG[@]+"${PROFILE_FLAG[@]}"}
  LIBS+=("$ROOT/target/$t/$CONFIG/libpet_core.a")
done

OUT="$ROOT/target/universal/$CONFIG"
mkdir -p "$OUT"
lipo -create "${LIBS[@]}" -output "$OUT/libpet_core.a.tmp"
# Only replace when contents change, so Xcode/SwiftPM don't relink needlessly.
if ! cmp -s "$OUT/libpet_core.a.tmp" "$OUT/libpet_core.a" 2>/dev/null; then
  mv "$OUT/libpet_core.a.tmp" "$OUT/libpet_core.a"
else
  rm "$OUT/libpet_core.a.tmp"
fi
echo "Built $OUT/libpet_core.a ($(lipo -archs "$OUT/libpet_core.a"))"
