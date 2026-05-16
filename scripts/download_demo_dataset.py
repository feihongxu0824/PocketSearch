#!/usr/bin/env python3
"""
Download a 10k-photo subset of the Unsplash Lite dataset (CC0 / Unsplash
License) for showcasing the photo search demo.

The Unsplash Lite dataset is a public, free-to-use collection of ~25k
high-quality photos: https://unsplash.com/data

Why this matters for the demo: CLIP-style models look much sharper when
the candidate pool is large (10k+) AND visually diverse. A drawer full
of WeChat screenshots searches like garbage. Unsplash gives us 25k
professionally curated photos covering people / animals / food / nature
/ cityscape / night / weather / close-ups out of the box.

Usage:
    # 1. Download the Unsplash Lite metadata zip (~100 MB) from
    #    https://unsplash.com/data/lite/latest
    #    Unzip and place `photos.tsv000` at `data/unsplash_lite/photos.tsv000`.
    #
    # 2. Run this script. It will download N random photos at 1080p JPEG
    #    into `data/demo_album/`.
    python scripts/download_demo_dataset.py --count 10000

    # Resume / re-run is idempotent: already-downloaded files are skipped.

License note: every photo retains its individual Unsplash License. You
may use them in personal or commercial projects, but redistribution of
the entire dataset requires attribution. See:
https://unsplash.com/license
"""

from __future__ import annotations

import argparse
import csv
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: 'requests' is required. Install via: pip install requests tqdm",
          file=sys.stderr)
    sys.exit(2)

try:
    from tqdm import tqdm
except ImportError:
    print("ERROR: 'tqdm' is required. Install via: pip install requests tqdm",
          file=sys.stderr)
    sys.exit(2)


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_TSV_DIR = REPO_ROOT / "data" / "unsplash_lite"
# Unsplash has shipped both `photos.tsv000` (older) and `photos.csv000`
# (current) — internal format is identical (tab-separated). Accept both.
DEFAULT_TSV_CANDIDATES = (
    DEFAULT_TSV_DIR / "photos.tsv000",
    DEFAULT_TSV_DIR / "photos.csv000",
)
DEFAULT_TSV = DEFAULT_TSV_CANDIDATES[0]  # canonical name for --tsv help text
DEFAULT_OUT = REPO_ROOT / "data" / "demo_album"


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--count", type=int, default=10000,
                   help="Number of photos to download (default: 10000)")
    p.add_argument("--width", type=int, default=1080,
                   help="Image width in pixels (default: 1080)")
    p.add_argument("--quality", type=int, default=80,
                   help="JPEG quality 1-100 (default: 80)")
    p.add_argument("--workers", type=int, default=16,
                   help="Concurrent downloads (default: 16)")
    p.add_argument("--seed", type=int, default=42,
                   help="RNG seed for reproducible subset (default: 42)")
    p.add_argument("--tsv", type=Path, default=DEFAULT_TSV,
                   help="Path to photos.tsv000")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT,
                   help="Output directory")
    return p.parse_args()


def load_photo_urls(tsv_path: Path) -> list[tuple[str, str]]:
    """Return list of (photo_id, photo_image_url)."""
    # If the user-supplied / default path is missing, fall back to the
    # other accepted filename so `photos.tsv000` ↔ `photos.csv000` are
    # interchangeable without editing the command line.
    if not tsv_path.exists():
        for cand in DEFAULT_TSV_CANDIDATES:
            if cand.exists():
                print(f"    (using {cand.name} — {tsv_path.name} not found)")
                tsv_path = cand
                break
    if not tsv_path.exists():
        print(f"ERROR: TSV not found at {tsv_path}", file=sys.stderr)
        print("Download Unsplash Lite from https://unsplash.com/data/lite/latest",
              file=sys.stderr)
        print("Unzip and place photos.tsv000 (or photos.csv000) at:", file=sys.stderr)
        print(f"  {DEFAULT_TSV_DIR}/", file=sys.stderr)
        sys.exit(1)

    rows: list[tuple[str, str]] = []
    with tsv_path.open("r", encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            pid = row.get("photo_id", "").strip()
            url = row.get("photo_image_url", "").strip()
            if pid and url:
                rows.append((pid, url))
    return rows


def build_download_url(base_url: str, width: int, quality: int) -> str:
    """Append Imgix parameters for a 1080p JPEG."""
    sep = "&" if "?" in base_url else "?"
    return f"{base_url}{sep}w={width}&q={quality}&fm=jpg&auto=format"


def download_one(session: requests.Session, photo_id: str, url: str,
                 out_dir: Path, width: int, quality: int,
                 retries: int = 3) -> tuple[str, bool, str]:
    """Returns (photo_id, success, message)."""
    out_path = out_dir / f"{photo_id}.jpg"
    if out_path.exists() and out_path.stat().st_size > 0:
        return (photo_id, True, "skip")

    full_url = build_download_url(url, width, quality)
    last_err = ""
    for attempt in range(retries):
        try:
            resp = session.get(full_url, timeout=30, stream=True)
            resp.raise_for_status()
            tmp_path = out_path.with_suffix(".tmp")
            with tmp_path.open("wb") as fh:
                for chunk in resp.iter_content(chunk_size=64 * 1024):
                    if chunk:
                        fh.write(chunk)
            tmp_path.rename(out_path)
            return (photo_id, True, "ok")
        except Exception as exc:  # noqa: BLE001
            last_err = f"{type(exc).__name__}: {exc}"
            time.sleep(1.5 * (attempt + 1))
    return (photo_id, False, last_err)


def main() -> int:
    args = parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    print(f"==> Loading {args.tsv}")
    rows = load_photo_urls(args.tsv)
    print(f"    Found {len(rows):,} photos in metadata.")

    rng = random.Random(args.seed)
    rng.shuffle(rows)
    subset = rows[: args.count]
    print(f"==> Will download {len(subset):,} photos to {args.out}")
    print(f"    width={args.width} quality={args.quality} workers={args.workers}")

    session = requests.Session()
    session.headers.update({
        "User-Agent": "zvec-photo-search-demo/1.0 (+https://github.com/zvec-ai)",
    })

    ok = 0
    skip = 0
    fail = 0
    fail_log: list[tuple[str, str]] = []

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [
            pool.submit(download_one, session, pid, url,
                        args.out, args.width, args.quality)
            for pid, url in subset
        ]
        for fut in tqdm(as_completed(futures), total=len(futures),
                        desc="download", unit="img"):
            pid, success, msg = fut.result()
            if success and msg == "skip":
                skip += 1
            elif success:
                ok += 1
            else:
                fail += 1
                fail_log.append((pid, msg))

    print(f"\n==> Done.  ok={ok}  skip={skip}  fail={fail}")
    if fail_log:
        print("    First 5 failures:")
        for pid, err in fail_log[:5]:
            print(f"      {pid}: {err}")
        print("    Re-run the script to retry failed photos (idempotent).")

    total = sum(1 for _ in args.out.glob("*.jpg"))
    print(f"==> {total:,} JPEGs now in {args.out}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
