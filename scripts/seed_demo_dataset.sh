#!/usr/bin/env bash
#
# seed_demo_dataset.sh — push a Lorem-Picsum based demo gallery to a real
# Android device so the zvec photo-search demo has visually meaningful
# results to rank.
#
# Usage:
#   scripts/seed_demo_dataset.sh [-s SERIAL] [-n COUNT] [-w WIDTH] [-h HEIGHT]
#
# Examples:
#   # Push 220 default-size photos to the only attached device
#   scripts/seed_demo_dataset.sh
#
#   # Push 500 photos to a specific serial
#   scripts/seed_demo_dataset.sh -s 88d4d8e5 -n 500
#
# What this does:
#   1. Downloads N random-but-deterministic Lorem-Picsum JPEGs into a
#      throw-away tmp dir (uses `seed/zvecNNN` so reruns produce the
#      same images, useful for screenshot/demo reproducibility).
#   2. `adb push` everything to /sdcard/DCIM/Camera/.
#   3. Triggers a MediaStore scan so MediaProvider picks them up.
#   4. Reminds you to launch the app — the in-app cold-start sync
#      (IndexService.computeSyncPlan + VectorStore.deleteByIds) will
#      automatically purge stale records from prior datasets and
#      encode only the new photos.
#
# Pre-flight: `adb` must be on PATH. If you used Android Studio on macOS,
# add `~/Library/Android/sdk/platform-tools` to your PATH first.

set -euo pipefail

SERIAL=""
COUNT=220
WIDTH=1024
HEIGHT=768
TMP_DIR="${TMPDIR:-/tmp}/zvec_picsum_seed"
REMOTE_DIR="/sdcard/DCIM/Camera"
PKG="ai.zvec.zvec_photo_search"

while getopts "s:n:w:h:" opt; do
  case $opt in
    s) SERIAL="$OPTARG" ;;
    n) COUNT="$OPTARG" ;;
    w) WIDTH="$OPTARG" ;;
    h) HEIGHT="$OPTARG" ;;
    *) echo "Usage: $0 [-s SERIAL] [-n COUNT] [-w WIDTH] [-h HEIGHT]"; exit 2 ;;
  esac
done

if ! command -v adb >/dev/null 2>&1; then
  echo "ERROR: adb not on PATH. On macOS try:" >&2
  echo '  export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"' >&2
  exit 1
fi

ADB=(adb)
if [[ -n "$SERIAL" ]]; then
  ADB+=(-s "$SERIAL")
fi

if ! "${ADB[@]}" get-state >/dev/null 2>&1; then
  echo "ERROR: device not reachable. Run 'adb devices' to verify." >&2
  exit 1
fi

echo "==> Step 1/4: downloading $COUNT photos (${WIDTH}x${HEIGHT}) into $TMP_DIR"
mkdir -p "$TMP_DIR"
# Wipe stale files so a smaller --count run does not leave bigger sets behind.
find "$TMP_DIR" -maxdepth 1 -name "picsum_*.jpg" -delete 2>/dev/null || true

# Generate zero-padded sequence so file ordering is stable on-device.
PAD_WIDTH=$(printf '%s' "$COUNT" | wc -c | tr -d ' ')
seq -f "%0${PAD_WIDTH}g" 1 "$COUNT" | \
  xargs -P 8 -I{} curl -sL --max-time 30 \
    -o "$TMP_DIR/picsum_{}.jpg" \
    "https://picsum.photos/seed/zvec{}/$WIDTH/$HEIGHT"

DOWNLOADED=$(find "$TMP_DIR" -maxdepth 1 -name "picsum_*.jpg" | wc -l | tr -d ' ')
if [[ "$DOWNLOADED" != "$COUNT" ]]; then
  echo "ERROR: expected $COUNT files, got $DOWNLOADED — check network and retry." >&2
  exit 1
fi
TOTAL_BYTES=$(du -sh "$TMP_DIR" | awk '{print $1}')
echo "    downloaded $DOWNLOADED files ($TOTAL_BYTES)"

echo "==> Step 2/4: adb push to $REMOTE_DIR"
"${ADB[@]}" shell "mkdir -p $REMOTE_DIR" >/dev/null
"${ADB[@]}" push "$TMP_DIR/." "$REMOTE_DIR/" 2>&1 | tail -1

echo "==> Step 3/4: triggering MediaStore scan"
"${ADB[@]}" shell content call \
  --uri content://media/ \
  --method scan_volume \
  --arg external_primary >/dev/null
# Give the framework a moment to actually scan before counting.
sleep 3
INDEXED=$("${ADB[@]}" shell \
  "content query --uri content://media/external/images/media \
     --projection _id \
     --where \"_data like '%/DCIM/Camera/picsum%'\"" 2>/dev/null \
  | grep -c "^Row:" || true)
echo "    MediaStore now reports $INDEXED picsum_* images"

echo "==> Step 4/4: launch the app"
echo "    The IndexService cold-start sync will automatically:"
echo "      - drop stale records (photos no longer on device)"
echo "      - encode only the new photos"
echo
echo "    Run:"
if [[ -n "$SERIAL" ]]; then
  echo "      adb -s $SERIAL shell am start -n $PKG/.MainActivity"
else
  echo "      adb shell am start -n $PKG/.MainActivity"
fi
echo
echo "    Indexing $COUNT photos takes ~$((COUNT / 70 + 1)) minutes on a debug build."
echo "Done."
