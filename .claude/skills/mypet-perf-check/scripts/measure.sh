#!/usr/bin/env bash
# Average CPU and physical memory footprint of mypet under given settings, from kernel CPU-time accounting.
#   measure.sh <label> <settings-json> [seconds=30]
# Run from the mypet repo root after building build/MyPet.app.
# The user's saved settings are backed up and restored afterwards.
set -euo pipefail

LABEL="$1"; JSON="$2"; SECS="${3:-30}"
APP="build/MyPet.app/Contents/MacOS/MyPet"
DOMAIN="com.erag.mypet"; KEY="settings.v1"
[[ -x "$APP" ]] || { echo "error: $APP not found — build first" >&2; exit 1; }

# ps time is [[hh:]mm:]ss.cc
to_secs() { awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }

BACKUP="$(defaults export "$DOMAIN" - 2>/dev/null || true)"
restore() {
  if [[ -n "$BACKUP" ]]; then printf '%s' "$BACKUP" | defaults import "$DOMAIN" -; else defaults delete "$DOMAIN" "$KEY" 2>/dev/null || true; fi
}
trap restore EXIT

pkill -f "MyPet.app/Contents/MacOS/MyPet" 2>/dev/null || true
sleep 1
defaults write "$DOMAIN" "$KEY" -data "$(printf '%s' "$JSON" | xxd -p | tr -d '\n')"

"$APP" >/dev/null 2>&1 &
PID=$!
disown
sleep 5 # skip launch work
t1=$(ps -o time= -p "$PID" | to_secs); u1=$(ps -o utime= -p "$PID" | to_secs)
sleep "$SECS"
t2=$(ps -o time= -p "$PID" | to_secs); u2=$(ps -o utime= -p "$PID" | to_secs)
# Physical footprint is what Activity Monitor's "Memory" column shows; RSS also counts
# shared system pages and overstates our cost.
footprint=$(vmmap --summary "$PID" 2>/dev/null | awk '/^Physical footprint:/ {print $3; exit}')
kill "$PID" 2>/dev/null || true

printf '%-28s cpu %5.2f%%  (user %5.2f%%)  memory %s  over %ss\n' "$LABEL" \
  "$(echo "($t2-$t1)*100/$SECS" | bc -l)" "$(echo "($u2-$u1)*100/$SECS" | bc -l)" "${footprint:-?}" "$SECS"
