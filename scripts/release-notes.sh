#!/usr/bin/env bash
# Prints the CHANGELOG.md section for a version (used as the GitHub release body).
#   scripts/release-notes.sh 0.2.0
set -euo pipefail
VERSION="${1:?usage: release-notes.sh <version>}"
CHANGELOG="$(cd "$(dirname "$0")/.." && pwd)/CHANGELOG.md"
awk -v v="$VERSION" '
  $0 ~ "^## \\[?" v "\\]?([ -]|$)" { found = 1; next }
  found && /^## / { exit }
  found { print }
  END { if (!found) { print "error: no section for " v " in CHANGELOG.md" > "/dev/stderr"; exit 1 } }
' "$CHANGELOG" | sed -e '/./,$!d'
