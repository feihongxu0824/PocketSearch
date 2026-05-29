#!/usr/bin/env bash
#
# push_demo_to_ios.sh — import the demo album into macOS Photos.app and
# rely on iCloud Photos to mirror it onto the iPhone.
#
# iOS does not let third-party tools push directly into the Camera Roll,
# so the only stable path is:
#
#   data/demo_album/*.jpg
#       │
#       ▼  (this script: AppleScript / osascript)
#   macOS Photos.app  ──── iCloud Photos ────►  iPhone Photos
#
# Usage:
#   bash scripts/push_demo_to_ios.sh                       # default: data/demo_album → "PocketSearch demo"
#   bash scripts/push_demo_to_ios.sh path/to/dir
#   bash scripts/push_demo_to_ios.sh path/to/dir "Album Name"
#
# Pre-flight on the Mac:
#   - Photos.app has been opened at least once (so the system library exists).
#   - System Settings → Apple ID → iCloud → Photos: ON.
#   - Enough iCloud storage for the upload (10k × ~200 KB ≈ 2 GB).
#
# Pre-flight on the iPhone:
#   - Same Apple ID signed in.
#   - Settings → [Your Name] → iCloud → Photos: ON.
#   - "Optimize iPhone Storage" is fine — the demo only needs the photos
#     to appear in the gallery, not to be downloaded in full quality.
#
# Speed guidance:
#   - Photos.app local ingest:   ~5-15 min for 10k photos.
#   - iCloud upload:             ~10-30 min on a residential connection.
#   - iPhone download/visible:   ~10-30 min after upload finishes.
#   - Total wall clock:          plan ~1 hour for 10k.
#
# Why not just AirDrop / Image Capture?
#   - AirDrop tops out around 500 files per batch and saves to Files,
#     not Photos.
#   - Image Capture is one-way (device → Mac), no reverse direction.
#   - Finder "Sync Photos" requires turning OFF iCloud Photos on the
#     iPhone first, which most demo phones do not want to do.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${1:-${REPO_ROOT}/data/demo_album}"
ALBUM_NAME="${2:-PocketSearch demo}"
BATCH=200  # AppleScript event size — Photos handles ~200 files per call cleanly.

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: this script targets macOS Photos.app." >&2
  exit 2
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: source directory not found: $SRC_DIR" >&2
  echo "Run scripts/download_demo_dataset.py first." >&2
  exit 1
fi

JPEG_COUNT=$(find "$SRC_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) | wc -l | tr -d ' ')
if [[ "$JPEG_COUNT" -eq 0 ]]; then
  echo "ERROR: no JPEGs found in $SRC_DIR" >&2
  exit 1
fi

cat <<EOF
==> Source       : $SRC_DIR
==> JPEG count   : $JPEG_COUNT
==> Target album : "$ALBUM_NAME" (in macOS Photos.app)
==> Sync path    : Photos.app  →  iCloud Photos  →  iPhone

Reminders:
  - iCloud Photos must be ON on both this Mac and the iPhone.
  - Total wall clock ~1 hour for 10k photos.
  - Re-running is safe: "skip check duplicates" is enabled.

EOF

read -r -p "Proceed with import? [y/N] " ans
case "$ans" in
  y|Y|yes|YES) ;;
  *) echo "aborted."; exit 0 ;;
esac

# ----- 1. ensure album exists ------------------------------------------------

osascript >/dev/null <<APPLESCRIPT
tell application "Photos"
  activate
  if not (exists album "$ALBUM_NAME") then
    make new album named "$ALBUM_NAME"
  end if
end tell
APPLESCRIPT

# ----- 2. collect file list (absolute paths) ---------------------------------

FILES=()
while IFS= read -r -d '' f; do
  FILES+=("$f")
done < <(find "$SRC_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -print0)

TOTAL=${#FILES[@]}
echo "==> Importing $TOTAL files in batches of $BATCH"
echo

# ----- 3. batch import via AppleScript --------------------------------------

batch_idx=0
i=0
while (( i < TOTAL )); do
  end=$(( i + BATCH ))
  (( end > TOTAL )) && end=$TOTAL
  batch_idx=$(( batch_idx + 1 ))

  # Build AppleScript list literal: { POSIX file "p1", POSIX file "p2", ... }
  list=""
  for (( j=i; j<end; j++ )); do
    p="${FILES[j]}"
    # Escape backslashes first, then double quotes — order matters.
    p="${p//\\/\\\\}"
    p="${p//\"/\\\"}"
    if [[ -n "$list" ]]; then
      list+=", "
    fi
    list+="POSIX file \"$p\""
  done

  printf "    batch %3d (%5d / %5d) ... " "$batch_idx" "$end" "$TOTAL"

  if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Photos"
  import { $list } into album "$ALBUM_NAME" skip check duplicates true
end tell
APPLESCRIPT
  then
    echo "ok"
  else
    echo "FAILED"
    echo "    Photos.app rejected the batch. The most common cause is the"
    echo "    Photos.app dialog 'do you want to keep these in the library' —"
    echo "    open Photos.app, dismiss any dialog, then re-run this script."
    echo "    Re-running is idempotent (skip-duplicates is on)."
    exit 1
  fi

  i=$end
done

echo
cat <<EOF
==> Done. All $TOTAL files handed off to Photos.app.

Next:
  1. Watch the upload status in Photos.app:
       sidebar → "iCloud Photos"  (or Library → top toolbar)
     The blue progress bar tells you when uploads finish.

  2. On the iPhone, open Photos. Once iCloud sync completes, the
     "$ALBUM_NAME" album will appear automatically.

  3. Launch the demo app. The first cold-start sync will index the
     newly-arrived photos. Indexing 10k photos takes ~5-10 min on
     iPhone 13+ (release build).
EOF
