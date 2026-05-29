<div align="center">

# PocketSearch

**Describe it. Find it. On your phone, offline.**

*A unified, on-device search layer for personal data — starting with photos.*

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)]()
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.41-02569B.svg?logo=flutter)]()
[![Engine](https://img.shields.io/badge/zvec-on--device-success.svg)](https://github.com/zvec-ai/zvec-dart)

[English](README.md) · [中文](README_zh.md)

![Demo](docs/assets/demo_search.gif)

</div>

---

PocketSearch lets you find photos on your phone by *describing them* — no tags, no folders, no cloud round-trip. Powered by [zvec](https://github.com/zvec-ai/zvec-dart) (on-device vector DB) + [MobileCLIP-S1](https://github.com/apple/ml-mobileclip) running locally via [MNN](https://github.com/alibaba/MNN).

## 🎯 Vision

Personal data on a phone is fragmented across photos, notes, mail, messages, files and third-party apps — and most of it is too sensitive to leave the device. As mobile AI assistants get more capable, they need a **local retrieval layer** they can query without round-tripping to the cloud.

PocketSearch is our take on that layer. The product principle is simple:

- **Local-first.** Index, embed, retrieve and rank — all on the device. No upload, no socket calls in the default path.
- **Multi-source.** Photos today; notes, mail, files, screenshots / OCR, third-party app data next.
- **Dual-purpose.** A search box for humans, and a structured retrieval API for on-device agents.

We started with **photos** because the gallery is the largest, fastest-growing personal corpus on most phones — screenshots, receipts, whiteboards, chat captures — and users rarely remember filenames or dates, only *what was in the picture*.

## ⚡ Quick Start

> **Prerequisites**: Flutter ≥ 3.41, Xcode 15+ (iOS only), Android SDK (Android only).

### Common setup (both platforms)

```bash
git clone git@gitlab.alibaba-inc.com:xufeihong.xfh/PocketSearch.git
cd PocketSearch
flutter pub get
bash scripts/prepare_mnn_src.sh      # Download MNN source (~89 MB, cached in ~/.cache/)
```

### Android

```bash
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

That's it. Open the app, grant photo permission, done.

### iOS

1. Open Xcode and add your Apple ID: **Xcode → Settings → Accounts → "+"**
2. Open the workspace and configure signing:
   ```bash
   open ios/Runner.xcworkspace
   ```
   In Xcode: **Runner project → Signing & Capabilities → Team → select your account**
3. Connect your iPhone, select it as target, and press **▶ Run**.
4. First launch on device: go to **Settings → General → VPN & Device Management** → trust the developer certificate.

> After the first Xcode build, you can also use `flutter run -d <DEVICE_ID>` for subsequent runs.
> Find your device ID: `xcrun xctrace list devices`

### Model Preparation (only if models are missing)

The repo includes pre-converted `.mnn` models in `assets/models/`. If you need to re-export:

```bash
pip install torch mobileclip onnx onnxruntime
python scripts/export_onnx.py      # Export ONNX
bash scripts/convert_mnn.sh         # Convert to MNN → assets/models/
```

### Demo Dataset

```bash
bash scripts/seed_demo_dataset.sh   # 220 curated photos, zero download
# Or full 10K Unsplash Lite:
python scripts/download_demo_dataset.py --count 10000
bash scripts/push_demo_to_android.sh
```

---

## 🏗️ Architecture

```
"sunset over the ocean"
        │
        ▼
┌──────────────┐     ┌────────────┐     ┌────────────┐
│ MobileCLIP   │ ──▶ │   zvec     │ ──▶ │  Top-K     │
│ Text Encoder │     │ HNSW+scalar│     │  Results   │
│ (~90 ms)     │     │ (2–3 ms)   │     │            │
└──────────────┘     └────────────┘     └────────────┘
```

| Component | Role |
|---|---|
| [zvec](https://github.com/zvec-ai/zvec-dart) | On-device vector database (HNSW + scalar filtering) |
| [MNN](https://github.com/alibaba/MNN) | Mobile inference engine |
| MobileCLIP-S1 | Image/text embedding (512-dim) |

> Today the input is photos and the output is a ranked image list. The same pipeline — *encode → index → retrieve → fuse* — generalises to notes, mail, files and screenshot OCR. zvec sits at the retrieval layer; the upstream encoders evolve per data source.

---

## 📊 Performance

Measured on iPhone SE 3 (A15), release mode, 10K photo index.

| Metric | Value |
|---|---|
| Vector query | **2–3 ms** |
| End-to-end search | **90–120 ms** |
| Network traffic | **0 bytes** |
| Memory (10K vectors) | ~40 MB |

---

## 🔒 Privacy

The offline guarantee is not a policy — it's an **architecture**: zvec has zero socket calls, CLIP runs on local MNN runtime. The only optional network path is an LLM query rewriter (sends query text only, off by default).

---

## 🗺️ Roadmap

**Now — Photos.** Semantic search over the local gallery, background incremental indexing, hybrid query (vector + time + geo), optional LLM query rewriter (off by default).

**Next — More sources.** Screenshots OCR, notes, mail, files. BM25 keyword fusion alongside vector recall. Chinese-CLIP for native CJK queries. Stable retrieval API surface so an on-device agent can call it.

**Later — Unified context.** Cross-source fusion ranking, on-device summarisation of result sets, pluggable embedding models, query-time scalar filters expressed in natural language.

---

## 🧪 Testing

```bash
flutter test test/                   # Unit tests (~64 cases)
flutter test integration_test/       # On-device integration (20 cases)
```

---

## 📄 License

[Apache License 2.0](LICENSE)
