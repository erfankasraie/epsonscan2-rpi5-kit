#!/usr/bin/env bash
# Install Epson's 32-bit ARM (armv7l / armhf) non-free plugin next to the arm64 epsonscan2 build.
# The arm64 core launches  <epsonscan2 dir>/non-free-exec/es2intif  as a separate process and talks to it
# through pipes, so a 32-bit es2intif can serve a 64-bit core.
#
# Usage:  sudo bash install-epson-plugin-armhf.sh <epsonscan2-bundle...armv7l...tar.gz | epsonscan2-non-free-plugin...deb>
set -Eeuo pipefail
ROOT="${ROOT:-}"                                    # (testing only) alternate filesystem root
say()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[✓]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[✗]\033[0m %s\n' "$*" >&2; exit 1; }
trap 'die "Failed at line $LINENO."' ERR

[ $# -eq 1 ] && [ -f "$1" ] || die "Usage: sudo bash $0 <bundle.tar.gz | non-free-plugin.deb>"
[ "$(id -u)" -eq 0 ] || [ -n "$ROOT" ] || die "Run with sudo."
IN="$(readlink -f "$1")"

MULTI64="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo aarch64-linux-gnu)"
DIR64="$ROOT/usr/lib/$MULTI64/epsonscan2"           # where our arm64 build looks for non-free-exec
DIR32="$ROOT/usr/lib/arm-linux-gnueabihf/epsonscan2"
[ -d "$DIR64" ] || [ -n "$ROOT" ] || die "$DIR64 not found: install the arm64 epsonscan2 package first."


# armhf packages live on ports.ubuntu.com, while arm64 may come from archive.ubuntu.com (Ubuntu 26.04):
# pin existing sources to arm64 and add a ports source for armhf only.
fix_apt_sources() {
  local d="${APT_DIR:-$ROOT/etc/apt}" f tmp codename
  codename="$(. "$ROOT/etc/os-release"; echo "${VERSION_CODENAME:-}")"
  [ -n "$codename" ] || { warn "Cannot detect Ubuntu codename; skipping apt source fix."; return 0; }
  [ -e "$d/sources.list.d/epson-armhf-ports.sources" ] && return 0
  for f in "$d"/sources.list.d/*.sources; do
    [ -e "$f" ] || continue
    grep -qi '^URIs:.*\(ubuntu\.com\|ports\.ubuntu\)' "$f" || continue
    cp -a "$f" "$f.bak-armhf"
    awk 'function flush(){ if(n>0){ for(i=1;i<=n;i++) print buf[i]; if(hastypes && !hasarch) print "Architectures: arm64"; } n=0; hastypes=0; hasarch=0 }
         /^[[:space:]]*$/ { flush(); print; next }
         { buf[++n]=$0; if($0 ~ /^Types:/) hastypes=1; if($0 ~ /^Architectures:/) hasarch=1 }
         END { flush() }' "$f.bak-armhf" > "$f"
  done
  if [ -s "$d/sources.list" ]; then   # legacy format
    cp -a "$d/sources.list" "$d/sources.list.bak-armhf"
    sed -i -E '/^deb(-src)? +[^[]/ s/^(deb(-src)?) +/\1 [arch=arm64] /' "$d/sources.list"
  fi
  mkdir -p "$d/sources.list.d"
  cat > "$d/sources.list.d/epson-armhf-ports.sources" <<SRC
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports
Suites: $codename $codename-updates $codename-security $codename-backports
Components: main universe restricted multiverse
Architectures: armhf
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
SRC
  ok "apt sources adjusted (backups: *.bak-armhf)."
}

# ---- 1) can this system run 32-bit ARM programs? ----
if [ -z "$ROOT" ]; then
  [ "$(dpkg --print-architecture)" = "arm64" ] || warn "Host is not arm64; this script targets Raspberry Pi 5."
  if ! dpkg --print-foreign-architectures | grep -qx armhf; then say "Enabling armhf multiarch…"; dpkg --add-architecture armhf; fi
  fix_apt_sources
  say "Installing 32-bit runtime libraries (apt)…"
  apt-get update || warn "apt update reported errors; continuing."
  DEBIAN_FRONTEND=noninteractive apt-get install -y libc6:armhf libstdc++6:armhf libgcc-s1:armhf zlib1g:armhf \
      libusb-1.0-0:armhf || die "Could not install armhf libraries. Check that armhf is available in your apt sources (ports.ubuntu.com)."
  # optional libs some plugin binaries link against
  DEBIAN_FRONTEND=noninteractive apt-get install -y libpng16-16t64:armhf libjpeg-turbo8:armhf libtiff6:armhf libssl3t64:armhf 2>/dev/null || true
  LD32="$(ls /lib/ld-linux-armhf.so.3 /usr/lib/arm-linux-gnueabihf/ld-linux-armhf.so.3 2>/dev/null | head -n1 || true)"
  [ -n "$LD32" ] || die "32-bit loader (ld-linux-armhf.so.3) missing."
  "$LD32" --version >/dev/null 2>&1 && ok "32-bit ARM programs can run on this kernel." \
     || die "Kernel cannot run 32-bit ARM binaries (CONFIG_COMPAT / AArch32 off). Stop here — this approach won't work on this system."
fi

# ---- 2) unpack the plugin ----
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
case "$IN" in
  *.tar.gz|*.tgz) say "Unpacking bundle…"; tar -xzf "$IN" -C "$TMP" ;;
  *.deb)          cp "$IN" "$TMP/" ;;
  *) die "Unsupported file: $IN" ;;
esac
PLUGDEB="$(find "$TMP" -name '*non-free-plugin*.deb' | head -n1 || true)"
[ -n "$PLUGDEB" ] || PLUGDEB="$(find "$TMP" -maxdepth 3 -name '*.deb' | head -n1 || true)"
[ -n "$PLUGDEB" ] || die "No .deb found in the input."
say "Plugin package: $(basename "$PLUGDEB")  ($(dpkg-deb -f "$PLUGDEB" Architecture 2>/dev/null || echo '?'), $(dpkg-deb -f "$PLUGDEB" Version 2>/dev/null || echo '?'))"
X="$TMP/x"; mkdir -p "$X"; dpkg-deb -x "$PLUGDEB" "$X"

EXEC="$(find "$X" -type d -name non-free-exec | head -n1 || true)"
[ -n "$EXEC" ] || die "non-free-exec directory not found in the package (is this the non-free plugin?)."
[ -e "$EXEC/es2intif" ] || die "es2intif is not in this package."
PROOT="$(dirname "$EXEC")"
file "$EXEC/es2intif" | grep -q 'ARM' || warn "es2intif does not look like an ARM binary: $(file "$EXEC/es2intif")"

# ---- 3) install: real files under the armhf path, symlinks from the arm64 path ----
say "Installing into $DIR32 …"
mkdir -p "$DIR32"
cp -a "$PROOT"/. "$DIR32"/
chmod 0755 "$DIR32/non-free-exec/"* 2>/dev/null || true
mkdir -p "$DIR64"
for d in "$DIR32"/*; do
  n="$(basename "$d")"
  if [ ! -e "$DIR64/$n" ] || [ -L "$DIR64/$n" ]; then ln -sfn "$d" "$DIR64/$n"; fi
done
# arch-independent data (firmware etc.)
SHAREDIR="$(find "$X" -type d -path '*/usr/share/epsonscan2' | head -n1 || true)"
if [ -n "$SHAREDIR" ]; then mkdir -p "$ROOT/usr/share/epsonscan2"; cp -a "$SHAREDIR"/. "$ROOT/usr/share/epsonscan2"/; fi
ok "Files installed."
# epsonscan2 (Engine::FindConnectionType) treats the file below as the marker for "non-free plugin installed".
# If it is missing, Open() fails immediately with "Unable to communicate with the scanner" for es2intif models.
# Keep a real file if the bundle ships one; otherwise create a harmless placeholder (only needed for OCR auto-rotate).
MARK="$ROOT/usr/libexec/epsonscan2-ocr/ocr-engine-getrotate"
if [ ! -e "$MARK" ]; then
  mkdir -p "$(dirname "$MARK")"
  printf '#!/bin/sh\nexit 1\n' > "$MARK"
  chmod 0755 "$MARK"
  ok "Created plugin marker $MARK (placeholder; OCR auto-rotate unavailable)."
fi


# ---- 4) checks ----
say "Plugin files for the V39 family (GT-S650 / ES0142 / ES010D):"
find "$DIR32" \( -iname '*gt-s650*' -o -iname '*es0142*' -o -iname '*es010d*' -o -iname 'libesintA1*' \) | sed 's/^/    /' || true
if [ -z "$(find "$DIR32" -iname '*gt-s650*' 2>/dev/null)" ]; then
  warn "No 'gt-s650' library found: this plugin version may NOT support the Perfection V39."
fi
if [ -z "$ROOT" ]; then
  say "Checking that es2intif's libraries resolve (32-bit)…"
  MISSING="$(LD_TRACE_LOADED_OBJECTS=1 LD_LIBRARY_PATH="$DIR32/non-free-exec:$DIR32:$DIR32/libexec" "$LD32" "$DIR32/non-free-exec/es2intif" 2>&1 | grep -i 'not found' || true)"
  if [ -n "$MISSING" ]; then warn "Missing libraries:"; echo "$MISSING" | sed 's/^/    /'; else ok "All libraries found."; fi
  echo; ok "Done. Replug the scanner, then test as your normal user:"
  echo "    epsonscan2 --list"; echo "    epsonscan2 --get-status"; echo "    epsonscan2   # GUI, press Next"
fi
