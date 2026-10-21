#!/usr/bin/env bash
# Example kiosk wrapper around Epson Scan 2's own command-line mode (headless).
# NOTE: written from the epsonscan2 source (--create / --scan); not tested on a live kiosk. Adjust to your needs.
#   kiosk-scan.sh [output-file]
# Scan settings (DPI, format, folder, ...) live in the SF2 file: create with `epsonscan2 --create`,
# edit with `epsonscan2 --edit <file.SF2>` (GUI) and put the path in SF2=...
set -euo pipefail
SF2="${SF2:-$HOME/.config/kiosk-scan/Settings.SF2}"
OUT="${1:-}"
mkdir -p "$(dirname "$SF2")"
if [ ! -f "$SF2" ]; then
  ( cd "$(dirname "$SF2")" && epsonscan2 --create && mv -f DefaultSettings.SF2 "$SF2" )
  echo "Created default settings: $SF2  (edit with: epsonscan2 --edit $SF2)"
fi
STAMP="$(mktemp)"; trap 'rm -f "$STAMP"' EXIT
epsonscan2 --scan "$SF2"
# By default Epson saves into the user's Pictures folder unless the SF2 says otherwise.
NEW="$(find "$HOME/Pictures" -type f -newer "$STAMP" 2>/dev/null | sort | tail -n 1 || true)"
[ -n "$NEW" ] || { echo "No new file found after scan." >&2; exit 1; }
if [ -n "$OUT" ]; then mv -f "$NEW" "$OUT"; echo "$OUT"; else echo "$NEW"; fi
