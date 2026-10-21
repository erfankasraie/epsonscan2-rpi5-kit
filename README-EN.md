# Epson Scan 2 on Raspberry Pi (arm64) — install & debug kit

Tested: Raspberry Pi 5, Ubuntu 26.04 arm64, Epson Perfection V39 / GT-S650 (USB 04b8:013d).

## Problem
Scanner is *detected* but scanning fails: `Unable to communicate with the scanner` (epsonscan2) / `Error during device I/O` (xsane, scanimage).

## Root causes
1. Models with USB PID `013a 013b 013c 013d 013e 013f 0142 014a` (e.g. V39) talk through a closed helper **`es2intif`**, which is *not* in Epson's open source. It ships only in the non-free plugin, and Epson publishes it for x86_64, i686 and **armv7l (32-bit)** — no aarch64.
2. `Engine::FindConnectionType()` returns "no plugin" if `/usr/libexec/epsonscan2-ocr/ocr-engine-getrotate` is missing, and `Open()` then fails instantly (never touching USB).
3. Not the cause: USB power (tested with a split cable).

Fix: build the open-source core for arm64, run the 32-bit ARM `es2intif` from the armv7l bundle (the core spawns it via `execl` and talks over pipes, so mixed 64/32-bit works), and make sure the marker file exists.

## Quick start
```bash
unzip epsonscan2-rpi5-kit.zip && cd epsonscan2-rpi5-kit
# put Epson's  epsonscan2-bundle-*armv7l*.deb.tar.gz  into plugin/  (or: bash scripts/download-plugin.sh)
bash install-all.sh          # ~20-40 min (compiles the core)
epsonscan2                   # GUI → Next
bash debug-scanner.sh        # diagnostic report → ~/epson-debug-report.txt
```
Headless: `epsonscan2 --create`, `epsonscan2 --scan DefaultSettings.SF2` (see `kiosk-scan.sh`, untested example).

## Notes
- Ubuntu 26.04: armhf packages are on `ports.ubuntu.com`; the plugin script adds that source (arm64-only for the main mirrors; backups `*.bak-armhf`).
- Core build patches: remove legacy `BOOST_NO_CXX11_RVALUE_REFERENCES`, `-std=gnu++14`, `-fpermissive`, `EPSON_OCR_INSTALL_PATH`, `CMAKE_POLICY_VERSION_MINIMUM=3.5`.
- The plugin is Epson's proprietary software and is not included; download it from Epson.
- Plugin download URLs/SHA256 are taken from the FreeBSD ports tree and were not opened from the author's network.
