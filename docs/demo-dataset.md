# Demo Dataset Setup

Why a curated dataset matters for the photo-search demo: CLIP-style
models look much sharper when the candidate pool is large (10k+) AND
visually diverse. A real phone gallery is mostly WeChat screenshots,
food-delivery vouchers, and document scans — searching that pool makes
even a perfect model look bad.

This guide produces a **10k-photo demo album** drawn from the
[Unsplash Lite Dataset](https://unsplash.com/data/lite/latest)
(~25k professionally curated, CC0 / Unsplash-licensed photos covering
people / animals / food / nature / cityscape / night / weather /
close-ups). Disk footprint: ~2 GB at 1080p / quality 80.

The whole setup is reproducible end-to-end from this repo.

## Step 1 — Get the Unsplash Lite metadata

1. Visit <https://unsplash.com/data/lite/latest>, accept the dataset
   terms, and download the ZIP (~100 MB).
2. Unzip and place the metadata file at:

   ```
   data/unsplash_lite/photos.tsv000   # older Unsplash exports
   data/unsplash_lite/photos.csv000   # current Unsplash exports — same TSV content, different name
   ```

   Either filename works — `download_demo_dataset.py` accepts both.
   (The `data/` directory is gitignored.)

## Step 2 — Download 10k JPEGs

```bash
pip install requests tqdm
python scripts/download_demo_dataset.py --count 10000
```

This shuffles the 25k URLs with a fixed seed (`42`) and downloads the
first 10k as 1080p JPEGs into `data/demo_album/`. Re-running is
idempotent — already-downloaded files are skipped, failed files are
retried.

Expected timing on a residential connection: **~30 minutes** at 16
concurrent workers.

Override defaults if needed:

```bash
python scripts/download_demo_dataset.py \
  --count 15000 \
  --width 1440 \
  --workers 32
```

## Step 3a — Push to Android

```bash
adb devices                # confirm exactly one device is connected
bash scripts/push_demo_to_android.sh
```

This pushes everything to `/sdcard/DCIM/zvec_demo/` and triggers the
media scanner. Expect 5–10 min over USB. After it finishes, open the
demo app — the photos appear automatically once you grant the media
permission.

## Step 3b — Push to iPhone

iOS does not let third-party tools push directly into the Camera
Roll. The only stable cable-free path is **Photos.app on Mac → iCloud
Photos → iPhone Photos**, and we ship a script that automates the Mac
side via AppleScript:

```bash
bash scripts/push_demo_to_ios.sh                 # default album: "zvec demo"
bash scripts/push_demo_to_ios.sh path/to/dir
bash scripts/push_demo_to_ios.sh path/to/dir "My Album"
```

The script:
1. Verifies the source dir.
2. Creates the target album in Photos.app if missing.
3. Imports all JPEGs in batches of 200 (skip-duplicates is on, so
   re-running is idempotent).
4. Prints next-step instructions for watching iCloud sync status.

**Pre-flight on the Mac:**
- Photos.app opened at least once (system library exists).
- System Settings → Apple ID → iCloud → Photos: **ON**.
- Enough iCloud storage (~2 GB for 10k photos).

**Pre-flight on the iPhone:**
- Same Apple ID signed in.
- Settings → [Your Name] → iCloud → Photos: **ON**.
  ("Optimize iPhone Storage" is fine.)

**Wall-clock budget for 10k photos:**
| Stage | Typical |
|---|---|
| Photos.app local ingest | 5–15 min |
| iCloud upload | 10–30 min |
| iPhone download / album visible | 10–30 min |
| **Total** | **~1 hour** |

Once the album appears on the iPhone, launch the demo app. The first
cold-start sync indexes everything (~5–10 min on iPhone 13+ release
build).

**Fallback options** (if iCloud is unavailable):
- **AirDrop in batches.** macOS Finder caps at ~500 files per batch;
  tedious but works without a cable.
- **Finder Sync Photos.** Requires turning OFF iCloud Photos on the
  iPhone first — usually not what you want for a demo phone.

## Step 4 — Run the demo queries

Use `assets/demo_queries.json` for repeatable, photogenic searches.
Twenty queries are curated across 8 categories with expected hit
counts; pick 4–6 for a tweet GIF.

A few that consistently produce striking results on the Unsplash Lite
subset:

- `sunset over the ocean`
- `neon lights of a downtown skyline`
- `latte art on a cup of coffee`
- `white cat sitting on a windowsill`
- `snowy mountain peak`

## Notes & gotchas

- **English only.** MobileCLIP-S1's text encoder is trained on English
  BPE; Chinese queries return garbage. Chinese support (likely via
  Chinese-CLIP) is a roadmap item.
- **License.** Each photo retains its individual Unsplash License — free
  for personal and commercial use, attribution appreciated. **Do not**
  redistribute the ZIP itself.
- **Disk usage.** 10k photos at 1080p / q80 average ~200 KB each → ~2 GB
  on disk. The `data/` directory is gitignored to keep the repo
  lightweight.
- **Reset.** To regenerate from scratch:
  ```bash
  rm -rf data/demo_album
  python scripts/download_demo_dataset.py
  ```
