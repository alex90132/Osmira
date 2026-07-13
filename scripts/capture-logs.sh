#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Osmira — capture device logs while reproducing a bug (e.g. YouTube hang).
#
# Streams the phone's logcat, keeping only Osmira-relevant lines (our native
# "Osmira/Vpn" tag, the Dart "[Osmira/…]" markers, the Go/WireGuard backend,
# and any crash/ANR), and writes them to logs/osmira-<timestamp>.log while
# also echoing to the terminal.
#
# Usage:
#   scripts/capture-logs.sh [device-serial]
#
# If no serial is given it uses the only connected device, or the first one.
# Debug builds emit these logs; release builds are silent by design.
# ─────────────────────────────────────────────────────────────────────────
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/logs"
mkdir -p "$OUT_DIR"

# Locate adb: PATH first, then the usual SDK spots.
ADB="$(command -v adb || true)"
for cand in "$HOME/Android/sdk/platform-tools/adb" "$HOME/Library/Android/sdk/platform-tools/adb" "/usr/lib/android-sdk/platform-tools/adb"; do
  [ -z "$ADB" ] && [ -x "$cand" ] && ADB="$cand"
done
if [ -z "$ADB" ]; then
  echo "error: adb not found (install platform-tools or add adb to PATH)" >&2
  exit 1
fi

# Pick the device.
DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  DEVICE="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
fi
if [ -z "$DEVICE" ]; then
  echo "error: no device connected. Run '$ADB devices' or pass a serial." >&2
  exit 1
fi

PKG="osmi.awg2"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$OUT_DIR/osmira-$TS.log"

echo "Device : $DEVICE"
echo "Package: $PKG"
echo "Output : $LOG"
echo "Filter : Osmira / AwgVpn / WireGuard / crashes"
echo "----------------------------------------------------------------------"
echo "Reproduce the bug now (connect VPN, open YouTube, wait for the hang)."
echo "Press Ctrl-C to stop. The RX-STALL line marks a frozen downlink."
echo "----------------------------------------------------------------------"

# Header for context.
{
  echo "=== Osmira log capture $TS ==="
  "$ADB" -s "$DEVICE" shell getprop ro.product.model 2>/dev/null | sed 's/^/model: /'
  echo "=============================="
} > "$LOG"

# Clear the ring buffer so we only see this session, then stream + filter.
# Keep only our own markers + crashes; system noise that merely mentions the
# package name (SurfaceFlinger/WindowManager) is deliberately excluded.
"$ADB" -s "$DEVICE" logcat -c 2>/dev/null || true
exec "$ADB" -s "$DEVICE" logcat -v time \
  | grep --line-buffered -E 'Osmira/|\[Osmira|WireGuard|GoBackend|E/flutter|AndroidRuntime|FATAL EXCEPTION|tombstoned' \
  | tee -a "$LOG"
