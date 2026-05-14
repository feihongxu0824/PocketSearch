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
2. Unzip and place `photos.tsv000` at:

   ```
   data/unsplash_lite/photos.tsv000
   ```

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

iOS is more locked-down. Two options that both work:

**Option A — Finder (fastest, recommended).**

1. Connect the iPhone via USB and trust the Mac.
2. In Finder, select the device → "Files" tab.
3. Drag `data/demo_album/` onto the demo app's container — but this
   only works if the demo exposes a `Files`-app share. We don't, so
   prefer Option B for this project.

**Option B — Photos app sync via Image Capture.**

1. Open `/Applications/Image Capture.app`.
2. Connect the iPhone and select it in the sidebar.
3. Switch the bottom-right popup to "Import to: Photos".
4. ⚠️  Image Capture imports *from* the device by default; for the
   reverse direction use `Photos` app:
   - Open `Photos.app`, drag `data/demo_album/` into the library, wait
     for it to ingest.
   - Connect iPhone, in Finder → Sync Photos → choose your library.

**Option C — AirDrop in batches.** macOS Finder can AirDrop ~500
files at a time. Tedious but works without a cable.

Whichever option you choose, ensure all 10k photos appear in the
**Photos** app on the device before launching the demo. The first
launch will trigger the cold-start sync; expect indexing to take
several minutes for 10k photos depending on the device.

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
