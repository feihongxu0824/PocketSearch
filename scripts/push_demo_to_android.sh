#!/usr/bin/env bash
# Push the demo album to a connected Android device's DCIM/zvec_demo and
# trigger the media scanner so photo_manager / MediaStore picks them up
# as if they were taken with the camera.
#
# Usage:
#   bash scripts/push_demo_to_android.sh             # push data/demo_album
#   bash scripts/push_demo_to_android.sh path/to/dir # push custom dir
#
# Notes:
#   * Requires `adb` on PATH and exactly one device connected.
#   * Pushing 10k JPEGs over USB takes ~5-10 min depending on cable speed.
#   * `adb push` is idempotent: rerunning skips files already on device
#     (it compares mtime).
#   * After pushing, we trigger MediaScanner so the new photos appear in
#     Gallery / photo_manager without rebooting the device.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${1:-${REPO_ROOT}/data/demo_album}"
REMOTE_DIR="/sdcard/DCIM/zvec_demo"

if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: adb not found on PATH." >&2
  echo "Install via: brew install android-platform-tools" >&2
  exit 2
fi

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "ERROR: source directory not found: ${SRC_DIR}" >&2
  echo "Run scripts/download_demo_dataset.py first." >&2
  exit 1
fi

DEVICE_COUNT=$(adb devices | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')
if [[ "${DEVICE_COUNT}" -ne 1 ]]; then
  echo "ERROR: expected exactly 1 connected device, found ${DEVICE_COUNT}." >&2
  echo "Run 'adb devices' to inspect." >&2
  exit 1
fi

JPEG_COUNT=$(find "${SRC_DIR}" -maxdepth 1 -name '*.jpg' | wc -l | tr -d ' ')
echo "==> Source: ${SRC_DIR} (${JPEG_COUNT} JPEGs)"
echo "==> Target: ${REMOTE_DIR} on device"

echo "==> Creating remote directory"
adb shell "mkdir -p ${REMOTE_DIR}"

echo "==> Pushing files (this may take several minutes)"
adb push "${SRC_DIR}/." "${REMOTE_DIR}/"

echo "==> Triggering media scanner on ${REMOTE_DIR}"
# `cmd media_rescan` works on Android 11+. Fall back to per-file
# MEDIA_SCANNER_SCAN_FILE broadcast if unavailable.
if ! adb shell "cmd content call --uri content://media --method scan_volume --arg external_primary" >/dev/null 2>&1; then
  echo "    (cmd media_rescan unavailable, falling back to broadcast)"
  adb shell "find ${REMOTE_DIR} -name '*.jpg' | head -100 | \
    xargs -I {} am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
    -d 'file://{}'" >/dev/null
  echo "    (only the first 100 files were broadcast; the system scanner"
  echo "     will pick up the rest within a few minutes)"
fi

echo "==> Done. Open the demo app and the photos should appear after"
echo "    granting media permission. If not, toggle airplane mode or"
echo "    reboot the device to force a full media rescan."
