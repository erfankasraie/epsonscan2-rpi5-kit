#!/usr/bin/env bash
# Try to download Epson's 32-bit ARM (Raspbian armv7l) bundle (contains the non-free plugin: es2intif).
# URLs/checksums come from the FreeBSD ports tree (distinfo/Makefile); not verified from the author's network.
# Usage: bash download-plugin.sh [dest-dir]      (default: ../plugin)
set -euo pipefail
DEST="${1:-$(cd "$(dirname "$0")/.." && pwd)/plugin}"; mkdir -p "$DEST"
FILE="epsonscan2-bundle-raspbian-6.7.70.0.armv7l.deb.tar.gz"
URL="https://download3.ebz.epson.net/dsc/f/03/00/16/14/43/372115c2c0d31756ecd13a187db6df9414b5348d/$FILE"
SHA="780e0862d9e3bd885d3de9b282ed1f40bdef09a465104e6f29ad9a90f08da377"
cd "$DEST"
if [ ! -s "$FILE" ]; then
  echo "[*] Downloading $FILE (~30 MB)…"
  if command -v wget >/dev/null; then wget -c -O "$FILE" "$URL"; else curl -fL -C - -o "$FILE" "$URL"; fi
fi
echo "[*] Verifying SHA256…"
echo "$SHA  $FILE" | sha256sum -c - || { echo "[!] Checksum mismatch: delete $DEST/$FILE and retry, or download the bundle manually (see README)."; exit 1; }
echo "[✓] OK: $DEST/$FILE"
