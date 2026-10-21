#!/usr/bin/env bash
# One-shot installer: Epson Scan 2 (built from source) + Epson's 32-bit ARM non-free plugin, for Raspberry Pi arm64.
#   bash install-all.sh                       # build core (if needed) + install plugin + quick check
#   bash install-all.sh --plugin FILE.tar.gz  # use a bundle you downloaded yourself
#   bash install-all.sh --skip-build          # core already installed
# Run as your normal user (sudo is used where needed).
set -Eeuo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SKIP_BUILD=0; PLUGIN=""
while [ $# -gt 0 ]; do case "$1" in
  --skip-build) SKIP_BUILD=1;; --plugin) PLUGIN="${2:?--plugin needs a file}"; shift;;
  -h|--help) sed -n 2,7p "$0"; exit 0;; *) echo "Unknown option $1" >&2; exit 2;; esac; shift; done
say(){ printf '\033[1;34m[*]\033[0m %s\n' "$*"; }; ok(){ printf '\033[1;32m[✓]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[✗]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run as your normal user, not root (sudo is used internally)."
[ "$(dpkg --print-architecture)" = "arm64" ] || die "This kit is for arm64 (Raspberry Pi 4/5 with 64-bit Ubuntu/Debian)."
sudo -v

# 1) core
if [ "$SKIP_BUILD" -eq 1 ] || dpkg -s epsonscan2 >/dev/null 2>&1; then
  ok "Epson Scan 2 core already installed — skipping build."
else
  say "Step 1/3: building Epson Scan 2 from source (20–40 min on a Pi 5)…"
  mkdir -p "$HERE/out"; ( cd "$HERE/out" && bash "$HERE/scripts/01-build-core.sh" )
fi

# 2) plugin bundle
if [ -z "$PLUGIN" ]; then
  PLUGIN="$(ls "$HERE"/plugin/*armv7l*.tar.gz "$HERE"/*armv7l*.tar.gz 2>/dev/null | head -n1 || true)"
fi
if [ -z "$PLUGIN" ]; then
  say "No plugin bundle found; trying to download it…"
  bash "$HERE/scripts/download-plugin.sh" "$HERE/plugin" || true
  PLUGIN="$(ls "$HERE"/plugin/*armv7l*.tar.gz 2>/dev/null | head -n1 || true)"
fi
[ -n "$PLUGIN" ] || die "Plugin bundle (epsonscan2-bundle-...armv7l.deb.tar.gz) not found. Download it from Epson (see README, section 'Download the plugin'), put it in $HERE/plugin/ and re-run."

say "Step 2/3: installing the non-free plugin from $(basename "$PLUGIN")…"
sudo bash "$HERE/scripts/02-install-plugin.sh" "$PLUGIN"

# 3) check
say "Step 3/3: checking…"
bash "$HERE/debug-scanner.sh" --quick || true
echo; ok "Done. Replug the scanner, then test:  epsonscan2   (or: bash debug-scanner.sh)"
