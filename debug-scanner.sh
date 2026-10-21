#!/usr/bin/env bash
# Epson Scan 2 on Raspberry Pi (arm64) — diagnostic report. Read-only; run as the normal user.
#   bash debug-scanner.sh          full check incl. a live test (needs the scanner connected)
#   bash debug-scanner.sh --quick  static checks only
# Writes ~/epson-debug-report.txt — attach it when asking for help.
set -u
QUICK=0; [ "${1:-}" = "--quick" ] && QUICK=1
REPORT="$HOME/epson-debug-report.txt"
exec > >(tee "$REPORT") 2>&1

PASS=0; FAIL=0; WARN=0
ok()   { printf '  [ OK ] %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n         -> %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
warn() { printf '  [WARN] %s\n' "$*"; WARN=$((WARN+1)); }
hdr()  { printf '\n== %s ==\n' "$*"; }

MULTI="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || gcc -dumpmachine 2>/dev/null || echo aarch64-linux-gnu)"
D64="/usr/lib/$MULTI/epsonscan2"
D32="/usr/lib/arm-linux-gnueabihf/epsonscan2"
MARK="/usr/libexec/epsonscan2-ocr/ocr-engine-getrotate"

hdr "System"
echo "date:    $(date)"; echo "kernel:  $(uname -srm)"
. /etc/os-release 2>/dev/null && echo "os:      ${PRETTY_NAME:-?}"
[ -r /proc/device-tree/model ] && echo "board:   $(tr -d '\0' </proc/device-tree/model)"
[ -r /proc/device-tree/chosen/power/max_current ] && echo "psu max_current (raw): $(xxd -p /proc/device-tree/chosen/power/max_current 2>/dev/null)  (0x1388 = 5000 mA)"
[ "$(uname -m)" = "aarch64" ] && ok "arm64 system" || warn "not aarch64 ($(uname -m)); this kit targets Raspberry Pi arm64"

hdr "Epson Scan 2 core"
if command -v epsonscan2 >/dev/null; then ok "epsonscan2 found: $(command -v epsonscan2)  [$(dpkg-query -W -f='${Version}' epsonscan2 2>/dev/null || echo 'no dpkg record')]"
else bad "epsonscan2 not installed" "run: bash install-all.sh"; fi
[ -e "$D64/libsane-epsonscan2.so" ] && ok "SANE backend library present" || bad "libsane-epsonscan2.so missing in $D64" "re-run scripts/01-build-core.sh"
[ -e /etc/sane.d/dll.d/epsonscan2 ] && ok "SANE backend registered (/etc/sane.d/dll.d/epsonscan2)" || warn "SANE dll.d entry missing (only matters for xsane/scanimage)"
ls /lib/udev/rules.d/60-epsonscan2.rules /usr/lib/udev/rules.d/60-epsonscan2.rules >/dev/null 2>&1 && ok "udev rules installed" || bad "udev rules missing" "re-run scripts/01-build-core.sh"

hdr "Scanner on USB"
EP="$(lsusb 2>/dev/null | grep -i '04b8' || true)"
if [ -n "$EP" ]; then ok "Epson device visible: $EP"; PID="$(echo "$EP" | sed -E 's/.*ID 04b8:([0-9a-f]{4}).*/\1/I')"; echo "  product id: 0x$PID"
  case "${PID,,}" in 013a|013b|013c|013d|013e|013f|0142|014a) echo "  -> this model REQUIRES the non-free plugin (es2intif)";; *) echo "  -> this model is not in the es2intif list (plugin may not be needed)";; esac
  BUS="$(echo "$EP" | sed -E 's/Bus ([0-9]+) Device ([0-9]+).*/\1 \2/')"; set -- $BUS
  DEV="/dev/bus/usb/$1/$2"; [ -r "$DEV" ] && [ -w "$DEV" ] && ok "device node readable/writable: $DEV" || bad "no permission on $DEV ($(ls -l "$DEV" 2>/dev/null))" "replug scanner (udev rule sets mode 0666) or reboot"
else bad "no Epson USB device (vendor 04b8)" "check cable/power switch; replug"; fi

hdr "Non-free plugin (needed by V39 and other es2intif models)"
if [ -x "$D64/non-free-exec/es2intif" ]; then ok "es2intif present"; T="$(file -L "$D64/non-free-exec/es2intif" 2>/dev/null)"; echo "  $T"
  case "$T" in *"ARM,"*"32-bit"*|*"32-bit"*"ARM"*) echo "  (32-bit ARM build — expected on Pi)";; esac
else bad "es2intif missing: $D64/non-free-exec/es2intif" "run: sudo bash scripts/02-install-plugin.sh plugin/<bundle>.tar.gz"; fi
LD32="$(ls /lib/ld-linux-armhf.so.3 /usr/lib/arm-linux-gnueabihf/ld-linux-armhf.so.3 2>/dev/null | head -n1)"
if [ -n "$LD32" ] && "$LD32" --version >/dev/null 2>&1; then ok "kernel can run 32-bit ARM programs"; else bad "cannot run 32-bit ARM programs" "install libc6:armhf (02-install-plugin.sh does it); if it still fails the kernel lacks 32-bit support"; fi
if [ -n "$LD32" ] && [ -e "$D32/non-free-exec/es2intif" ]; then
  MISSING="$(LD_TRACE_LOADED_OBJECTS=1 LD_LIBRARY_PATH="$D32/non-free-exec:$D32:$D32/libexec" "$LD32" "$D32/non-free-exec/es2intif" 2>&1 | grep -i 'not found' || true)"
  [ -z "$MISSING" ] && ok "es2intif: all 32-bit libraries resolve" || bad "es2intif misses libraries: $MISSING" "sudo apt install <package>:armhf for each missing lib"
fi
if [ -x "$MARK" ]; then ok "plugin marker exists: $MARK"; else bad "plugin marker missing: $MARK  (THIS CAUSES 'Unable to communicate with the scanner')" "sudo bash scripts/02-install-plugin.sh <bundle>   (or: sudo mkdir -p /usr/libexec/epsonscan2-ocr; printf '#!/bin/sh\\nexit 1\\n' | sudo tee $MARK; sudo chmod 755 $MARK)"; fi
find "$D32" -iname '*gt-s650*' 2>/dev/null | grep -q . && ok "V39/GT-S650 plugin library found" || warn "no 'gt-s650' library under $D32 (plugin version may not support V39)"

if [ "$QUICK" -eq 0 ]; then
  hdr "Live test: epsonscan2 --list / --get-status (max 40 s)"
  rm -rf /tmp/epson; mkdir -p /tmp/epson
  echo "-- --list:";       timeout 40 epsonscan2 --list 2>&1 | head -n 10
  echo "-- --get-status:"; timeout 40 epsonscan2 --get-status 2>&1 | head -n 15
  LOG=/tmp/epson/epsonscan2/epsonscan2.log
  if [ -s "$LOG" ]; then
    echo "-- log (noise removed; first 40 lines):"; grep -a -v -E "ModelInfo|GetModelIDFromProductID|UsbFinder" "$LOG" | cut -c1-200 | head -n 40
    grep -a -q "Open.*Enter" "$LOG" && ! grep -a -q "ESScanner.*Open" "$LOG" && echo "  hint: Open() returned immediately -> check the plugin marker above"
  else echo "  (no log produced)"; fi
fi

hdr "Summary"
echo "  OK=$PASS  WARN=$WARN  FAIL=$FAIL"
echo "  report saved: $REPORT"
[ "$FAIL" -eq 0 ] && echo "  All static checks passed." || echo "  Fix the [FAIL] items (top to bottom), then re-run."
