#!/usr/bin/env bash
# One-time setup of mypet's update-signing key (EdDSA / ed25519). Run it yourself, once.
#   scripts/sparkle-keys.sh            create (or reuse) the key and write the public key to project.yml
#   scripts/sparkle-keys.sh --github   also store the private key as the SPARKLE_PRIVATE_KEY repo secret
#
# Where the keys live:
#   private key → your login Keychain (Sparkle's generate_keys puts it there) and, with --github,
#                 an encrypted GitHub Actions secret. It is never written into the repository.
#   public key  → macos/project.yml (SPARKLE_PUBLIC_KEY). Safe to commit; every build embeds it.
#
# Keep a backup of the private key (e.g. `generate_keys -x` into a password manager). If you lose
# it, existing installs can't verify new updates and users must reinstall manually.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/macos/.build/artifacts/sparkle/Sparkle/bin"
REPO="eramitgupta/my-pet"
if [[ ! -x "$BIN/generate_keys" ]]; then
  echo "Sparkle tools not found; resolving the Swift package…"
  GIT_TERMINAL_PROMPT=0 swift package --package-path "$ROOT/macos" resolve
fi

echo "▸ Creating or reusing the Sparkle key in your login Keychain (macOS may ask for permission)"
"$BIN/generate_keys" >/dev/null
PUBLIC_KEY="$("$BIN/generate_keys" -p)"
[[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || { echo "error: unexpected public key: $PUBLIC_KEY" >&2; exit 1; }
echo "  public key: $PUBLIC_KEY"

echo "▸ Writing SPARKLE_PUBLIC_KEY into macos/project.yml"
/usr/bin/sed -i '' "s#^\\( *SPARKLE_PUBLIC_KEY: *\\).*#\\1\"$PUBLIC_KEY\"#" "$ROOT/macos/project.yml"
grep -q "SPARKLE_PUBLIC_KEY: \"$PUBLIC_KEY\"" "$ROOT/macos/project.yml" || { echo "error: couldn't update project.yml" >&2; exit 1; }
if command -v xcodegen >/dev/null; then (cd "$ROOT/macos" && xcodegen generate >/dev/null) && echo "  regenerated mypet.xcodeproj"; fi

if [[ "${1:-}" == "--github" ]]; then
  command -v gh >/dev/null || { echo "error: install the GitHub CLI (brew install gh) and run 'gh auth login'" >&2; exit 1; }
  read -r -p "Store the private key as the SPARKLE_PRIVATE_KEY secret of $REPO? [y/N] " ok
  if [[ "$ok" =~ ^[Yy]$ ]]; then
    TMP="$(mktemp -d)"; chmod 700 "$TMP"
    trap 'rm -P "$TMP/key" 2>/dev/null; rm -rf "$TMP"' EXIT
    "$BIN/generate_keys" -x "$TMP/key"
    gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" < "$TMP/key"
    echo "  ✓ secret stored; the temporary export has been erased"
  fi
fi

echo "✓ Done. Commit macos/project.yml (it contains only the public key)."
