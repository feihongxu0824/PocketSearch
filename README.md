# Zvec Photo Search

On-device semantic photo search for Android & iOS. Search your photo gallery using natural language — fully offline, fully private.

**Powered by [zvec](https://github.com/zvec-ai/zvec-dart) + MobileCLIP + MNN.**

## What It Does

Type a text description (e.g. "sunset at the beach", "cat sleeping") and instantly find matching photos from your gallery. Everything runs on-device:

- **No cloud APIs** — your photos never leave your phone
- **No internet required** — works in airplane mode
- **Sub-50ms search** — from thousands of photos

## Architecture

```
User Input ("sunset")
     │
     ▼
┌─────────────┐     ┌─────────────┐     ┌──────────┐
│ BPE Tokenize │ ──▶ │ MNN CLIP    │ ──▶ │ zvec     │ ──▶ Results
│ (< 1ms)     │     │ Text Encoder│     │ query    │
│             │     │ (~25ms)     │     │ (< 1ms)  │
└─────────────┘     └─────────────┘     └──────────┘
```

### Indexing Pipeline (background)

```
Photo Gallery
     │
     ▼
┌─────────────┐     ┌─────────────┐     ┌──────────┐
│ Read + Crop  │ ──▶ │ MNN CLIP    │ ──▶ │ zvec     │
│ + Normalize  │     │ Image Enc.  │     │ insert   │
│             │     │ (~100ms)    │     │          │
└─────────────┘     └─────────────┘     └──────────┘
```

## Tech Stack

| Component | Role |
|-----------|------|
| [zvec](https://github.com/zvec-ai/zvec-dart) 0.4.0 | On-device vector database (fully open source) |
| [MNN](https://github.com/alibaba/MNN) via [mnn.dart](https://pub.dev/packages/mnn) | Mobile inference engine |
| MobileCLIP-S1 | Cross-modal image/text embedding model |
| photo_manager | System photo gallery access |
| Flutter | Cross-platform UI |

## Getting Started

### Prerequisites

- Flutter SDK >= 3.10
- Android device (API 24+) or iOS device (15+)
- Python 3.9+ (for model conversion)
- MNN toolkit (for ONNX → MNN conversion)

### 1. Prepare Models

```bash
# Install Python dependencies
pip install torch mobileclip onnx onnxruntime

# Download MobileCLIP-S1 checkpoint
# (follow instructions at https://github.com/apple/ml-mobileclip)

# Export to ONNX
python scripts/export_onnx.py

# Convert to MNN (requires MNNConvert in PATH)
bash scripts/convert_mnn.sh
```

After conversion, you should have:
- `assets/models/mobileclip_s1_image_encoder.mnn`
- `assets/models/mobileclip_s1_text_encoder.mnn`

### 2. Prepare Tokenizer Vocab

Place the CLIP BPE vocabulary file at `assets/tokenizer/bpe_vocab.json`.

### 3. Build & Run

```bash
flutter pub get
flutter run
```

On Android, the first launch will request **photo gallery permission**
(`READ_MEDIA_IMAGES` on Android 13+). Once granted, the app starts an
incremental cold-start sync (see *Cold-start sync* below) and indexing
progress is shown in the status bar.

On iOS, the project is **real-device validated on iPhone (iOS 18)**.

The iOS Xcode workspace (`ios/Runner.xcodeproj`, `ios/Runner.xcworkspace`,
`ios/RunnerTests/`, `ios/Podfile.lock`) is **not committed to git** —
following the [`zvec-ai/zvec-dart`](https://github.com/zvec-ai/zvec-dart)
convention, anything Flutter/CocoaPods can regenerate stays out of
history so contributors don't accidentally commit their own signing
team or bundle id. To build for iOS the first time on a fresh clone:

```bash
# 1. Regenerate the Xcode workspace + RunnerTests scaffold.
#    Existing files (Info.plist, AppDelegate.swift, Podfile, …) are
#    preserved — flutter create only fills in the missing scaffolds.
flutter create --platforms=ios --org ai.zvec --project-name zvec_photo_search .

# 2. Install CocoaPods dependencies.
cd ios && pod install && cd ..

# 3. Open the workspace in Xcode and set your *Signing Team* under
#    Runner → Signing & Capabilities (a free Apple Developer account
#    works for sideloading to your own device).
open ios/Runner.xcworkspace

# 4. Build / run.
flutter build ios --release       # produces a 230-ish MB Runner.app
# or, on a connected iPhone:
flutter run --release
```

The first launch shows the system photo-library permission dialog
(declared as `NSPhotoLibraryUsageDescription` in
[`ios/Runner/Info.plist`](ios/Runner/Info.plist)). After granting,
the same cold-start sync runs.

For sideloaded builds you also need to **trust the developer
certificate** on the device (Settings → General → VPN & Device
Management → your Apple ID → Trust) before the app can launch.

## Browse & Share Results

Tap any tile in the result grid to open a full-screen preview
([`PhotoDetailPage`](lib/ui/widgets/photo_detail_page.dart)) with
pinch-to-zoom and a **native iOS / Android share sheet** wired through
[`share_plus`](https://pub.dev/packages/share_plus). The share action
exports the original asset from PhotoKit / MediaStore (not the
on-screen thumbnail), so AirDrop / Messages / etc. receive the
full-resolution image.

### 4. Seed a Demo Gallery (optional)

For compelling demo recordings you want a **large, visually diverse**
candidate pool — a real phone gallery is mostly chat screenshots and
coupons, which makes even a perfect CLIP look bad. Two seed paths:

**Recommended (1080p, ~10k photos, ~2 GB).** Use the Unsplash Lite
dataset for the tweet GIF / blog screenshots:

```bash
# 1. Download Unsplash Lite metadata (~100 MB) and unzip
#    photos.tsv000 to data/unsplash_lite/.
#    https://unsplash.com/data/lite/latest

# 2. Download 10k 1080p JPEGs to data/demo_album/  (~30 min).
pip install requests tqdm
python scripts/download_demo_dataset.py --count 10000

# 3a. Push to Android  (~5–10 min over USB, idempotent):
bash scripts/push_demo_to_android.sh

# 3b. Push to iPhone:  open data/demo_album/ in macOS Photos.app,
#     drag to library, then Finder → device → Sync Photos.
```

Full guide: [`docs/demo-dataset.md`](docs/demo-dataset.md). Twenty
curated English queries with expected hit counts live in
[`assets/demo_queries.json`](assets/demo_queries.json).

**Quick alternative (220 photos, no metadata download).** For a fast
functional smoke test on a fresh test phone:

```bash
scripts/seed_demo_dataset.sh           # 220 Lorem Picsum JPEGs
scripts/seed_demo_dataset.sh -n 500    # or any custom size
```

The app's cold-start sync drops records of any prior dataset and
encodes only the new photos — you can swap datasets freely without
rebuilding the app.

## Optional: LLM Query Agent

MobileCLIP-S1 was trained on English captions, so the out-of-the-box
search experience handles short English visual phrases best (`sunset at
the beach`, `cat sleeping on a couch`). For users who want to type the
way they think — long Chinese sentences, temporal references like
*"去年夏天海边玩的照片"* — the app ships with an **optional** LLM
query-agent layer that produces:

1. A **visual description** (4–15 English words) for CLIP matching.
2. Optional **date filters** (`date_start`, `date_end`) resolved from
   relative time expressions using the current date.
3. Optional **geo bounding-box** for location-aware filtering.

Two modes (Settings → gear icon on the home page, persisted via
`shared_preferences` on-device only):

| Mode | Network at search time | Best for |
|------|------------------------|----------|
| **Off** | none | The original 100%-offline demo — nothing changes. |
| **Remote** *(default)* | one HTTPS POST per search (query text only) | Natural language + date/geo filtering via any OpenAI-compatible API. |

> **Note:** Local on-device LLM mode was removed in May 2026 after
> real-device testing showed 1.5B-class models require 60s+ per
> inference on mobile hardware, making the UX unacceptable. The code
> remains in the repo for reference but is no longer exposed in the UI.

### Remote mode — OpenAI-compatible API

Default configuration ships with **DashScope** (Aliyun) `qwen-turbo`.
Also works with OpenAI, DeepSeek, Together, self-hosted Ollama, etc.
Only the query text is sent — never photos, never embeddings, never
gallery metadata. Image encoding, vector search and result rendering
remain 100% on-device.

| Field    | Default                                                | Notes |
|----------|--------------------------------------------------------|-------|
| Base URL | `https://dashscope.aliyuncs.com/compatible-mode/v1`    | Any OpenAI-compatible endpoint. |
| Model    | `qwen-turbo`                                           | Pick something small and fast — temperature is pinned to 0. |
| API Key  | (must be configured)                                   | Stored in `shared_preferences`. |

### Endpoint examples (all OpenAI-compatible)

| Provider       | Base URL                                                | Suggested model     |
|----------------|---------------------------------------------------------|---------------------|
| Aliyun DashScope (compat mode) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-turbo` |
| OpenAI         | `https://api.openai.com/v1`                             | `gpt-4o-mini`       |
| DeepSeek       | `https://api.deepseek.com/v1`                           | `deepseek-chat`     |
| Self-hosted Ollama | `http://<host>:11434/v1`                            | any installed chat model |

### Common guarantees

- **Always falls back.** Any HTTP error / timeout / empty response
  silently degrades to the original query so search never breaks.
  The strip below the search bar shows whether a rewrite happened
  (`LLM rewrote "…" → "…" (Xms)`) so the behaviour stays transparent.
- **Metadata filters displayed.** When the agent extracts date/geo
  filters, they are shown below the search bar with a 🔍 prefix.

Full configuration guide, prompt details, endpoint examples and
latency budget: [`docs/llm-query-rewriter.md`](docs/llm-query-rewriter.md).
Implementation lives in
[`lib/services/query_rewriter.dart`](lib/services/query_rewriter.dart)
(`QueryRewriter` interface + `IdentityQueryRewriter` no-op default +
`OpenAICompatibleQueryRewriter`).
Unit-tested at
[`test/services/query_rewriter_test.dart`](test/services/query_rewriter_test.dart)
and
[`test/services/settings_service_test.dart`](test/services/settings_service_test.dart).

## Cold-start Sync

On every launch [`IndexService`](lib/services/index_service.dart) runs a
three-step sync against the live gallery:

1. Page through MediaStore once to collect every visible asset id.
2. Compare with [`VectorStore.getAllPhotoIds()`](lib/services/vector_store.dart):
   IDs in the DB but no longer in the gallery are *stale* and get
   `deleteByIds`'d.
3. IDs present in both are marked already-indexed; only the remaining
   gallery entries are sent through CLIP.

This keeps cold start fast (no re-encode for unchanged libraries) and
makes "swap demo dataset" workflows safe — search results can never be
polluted by photos the user has already deleted.

The partition algorithm is implemented as a pure static function
[`IndexService.computeSyncPlan`](lib/services/index_service.dart) and
locked down by 8 unit tests in
[`test/services/index_sync_plan_test.dart`](test/services/index_sync_plan_test.dart)
plus an end-to-end zvec round-trip test in
[`integration_test/smoke_test.dart`](integration_test/smoke_test.dart).

## Test Matrix

| Layer | File | Coverage |
|---|---|---|
| Unit | `test/services/tokenizer_test.dart` | BPE tokenizer edge cases |
| Unit | `test/services/index_progress_test.dart` | progress state machine |
| Unit | `test/services/index_sync_plan_test.dart` | cold-start sync algorithm + iOS PhotoKit safePk (11 cases) |
| Unit | `test/services/search_response_test.dart` | search result shape |
| Unit | `test/utils/vec_math_test.dart` | cosine / L2 normalize |
| Unit | `test/ui/suggestion_chips_test.dart` | chip widget |
| Unit | `test/ui/photo_grid_test.dart` | grid + percentage label (zvec distance → similarity) |
| Integration (real device) | `integration_test/smoke_test.dart` | MNN encoders, zvec FFI, cross-modal alignment, VectorStore CRUD, cold-start sync end-to-end — 17 cases |

Run everything:

```bash
# First-time / after-reboot only — fetch MNN 3.5.0 source to /tmp/mnn_src
# (see Pitfall #10 below for why this is needed). Skip if already prepared.
bash scripts/prepare_mnn_src.sh

flutter test test/                             # unit (~40 cases, < 5s once cached)
flutter test integration_test/smoke_test.dart  # on a connected device
```

## Continuous Integration

GitHub Actions runs [`flutter analyze`](.github/workflows/ci.yml) on
every push and PR to `main`. Unit tests are not run on CI — the `mnn`
package triggers a full MNN native build on `flutter test`, which is
far more expensive than analyze and adds little signal. Run unit tests
locally before opening a PR.

## Known Pitfalls (battle-tested)

Things that silently broke during development — documented here so the
next contributor doesn't have to rediscover them:

1. **MNN text encoder input is `int32`, not `float32`.**
   `Tensor.host.cast<mnn.float32>()` plus `tokenIds[i].toDouble()`
   compiles fine and runs without crashing, but the bit-pattern
   reinterpret turns every token id into a huge garbage integer. The
   resulting text embedding lives in a different latent space than the
   image embedding, so cross-modal cosine collapses to a near-constant
   ~0.12 and "every query returns the same photos." Always cast as
   `mnn.int32` and write the raw integer.

2. **Android 13+ requires `READ_MEDIA_IMAGES`** in the manifest — not
   the legacy `READ_EXTERNAL_STORAGE`. `photo_manager`'s default
   `RequestType.common` also asks for video + audio permissions which
   are not declared, so the entire request returns `denied`. Use
   `RequestType.image` explicitly.

3. **`Collection.createAndOpen(path)` crashes if `path` already exists.**
   On second launch the DB directory is there from last time. Probe
   with `Directory(path).existsSync()` and call `Collection.open(path)`
   when it does.

4. **MIUI silently blocks `adb install` and `adb shell input tap`.** Pop
   up the install prompt manually the first time, and keep "USB
   debugging (Security settings)" enabled. `pm clear` is also blocked
   — rely on the in-app cold-start sync instead of clearing app data.

5. **`adb` may not be on PATH after a stock Android Studio install.**
   On macOS:
   `export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"`.

6. **iOS PhotoKit asset IDs contain `/` characters.** A real id looks
   like `83AB7AC8-XXXX-XXXX-XXXX-XXXXXXXXXXXX/L0/001`. zvec rejects
   any document whose primary key contains `/` with `invalid doc`,
   silently dropping every iOS photo at insert time. Sanitize the id
   (we replace `/` with `_`) before using it as a zvec pk — Android
   numeric ids are unaffected. See
   [`IndexService.safePk`](lib/services/index_service.dart).

7. **iPhone camera roll defaults to HEIC, which the bundled `stbi`
   decoder cannot parse.** `asset.file.readAsBytes()` returns raw HEIC
   bytes; the image preprocessor then sees zeros for every pixel and
   the resulting embedding is meaningless. Always pull pixels through
   `asset.thumbnailDataWithSize(256x256, JPEG)` so PhotoKit handles
   HEIC → JPEG decoding in-process. 256x256 is also the exact
   MobileCLIP image-encoder input size, so no extra resize is needed.

8. **`asset.file` on iOS is a sandbox temp copy that vanishes on
   restart.** If you store that path as the photo's display URI,
   `Image.file` silently fails on every cold start (broken-image
   icon). Store the raw `asset.id` instead and resolve thumbnails via
   `AssetEntity.fromId().thumbnailDataWithSize` at display time —
   that works on every launch on both platforms.

9. **zvec `MetricType.cosine` returns _distance_, not similarity.**
   Lower score == better match. The natural "sort descending,
   percentage = score * 100" pattern produces an inverted ranking
   (rank 1 shows 80%, rank N shows 88%). Sort _ascending_ and display
   `(1 - score) * 100` to match user intuition; threshold via a
   `maxDistance` cap (e.g. `<= 0.95`).

10. **`mnn-0.1.3` hard-codes `/tmp/mnn_src/MNN-3.5.0` as its CMake
    source.** It does NOT use FetchContent — the directory must
    already exist before `flutter test` (or any other build) runs.
    macOS purges `/tmp` on reboot, so on cold-start days you'll see
    `add_subdirectory given source ".../MNN-3.5.0" which is not an
    existing directory`. Run
    [`scripts/prepare_mnn_src.sh`](scripts/prepare_mnn_src.sh) to
    download (with mirror fallback for slow GitHub regions) and
    extract the source. The script is idempotent.


## Project Structure

```
lib/
├── main.dart                    # App entry point
├── app.dart                     # MaterialApp configuration
├── services/
│   ├── clip_service.dart        # MNN model lifecycle & inference
│   ├── index_service.dart       # Gallery scan & background indexing
│   ├── search_service.dart      # Text-to-image search orchestration
│   ├── vector_store.dart        # zvec wrapper
│   ├── tokenizer.dart           # BPE tokenizer (Dart)
│   ├── query_rewriter.dart      # Optional remote LLM query rewriter (OpenAI-compat)
│   ├── local_llm_rewriter.dart  # On-device LLM (deprecated, not exposed in UI)
│   └── settings_service.dart    # LLM mode (off/remote) + persistence
├── utils/
│   └── image_preprocessor.dart  # Image resize + normalize
└── ui/
    ├── home_page.dart           # Main search page (gear ⇒ settings)
    ├── settings_page.dart       # LLM mode picker (off/remote) + API endpoint config
    └── widgets/
        ├── photo_grid.dart      # Results grid (tap = open preview)
        ├── photo_detail_page.dart # Full-screen preview + share sheet
        ├── suggestion_chips.dart # Query suggestions
        └── index_status_bar.dart # Indexing progress (with failure surface)
```

## Performance (expected)

| Operation | Time |
|-----------|------|
| Model load (one-time) | ~1-2s |
| Text encoding | ~25ms |
| Image encoding | ~100ms |
| Vector query (5000 photos) | < 1ms |
| **Total search latency** | **< 50ms** |

## Key Differentiators vs Cloud Solutions

- **Privacy**: Photos never leave the device
- **Offline**: No internet dependency
- **Cost**: Zero API costs
- **Latency**: Sub-50ms vs 200-500ms for cloud roundtrip
- **Open Source**: zvec is fully open source (unlike ObjectBox's closed-source core)

## License

[Apache License 2.0](LICENSE)
