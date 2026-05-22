<div align="center">

# PocketSearch

**Describe it. Find it. On your phone, offline.**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)]()
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.41-02569B.svg?logo=flutter)]()
[![Engine](https://img.shields.io/badge/zvec-on--device-success.svg)](https://github.com/zvec-ai/zvec-dart)

![Demo](docs/assets/demo_search.gif)

[中文](#-中文版本)

</div>

---

## What Is This

**PocketSearch** is a **100% offline** semantic photo search app. It runs a CLIP multimodal embedding model and a vector database directly on your phone, letting you find photos with natural language:

> _"buildings I photographed in Beijing last summer"_ — one sentence, three intents, one local query.

No cloud. No network. No upload. **Photos, vectors, and metadata never leave your device.**

---

## Why

Neither iOS nor Android exposes a semantic photo search API to third-party apps. Apple has one internally (powering the Photos app), but it's closed. Android doesn't have one at all. So you're left with two choices:

- **Go cloud**: sync your entire album to someone else's server;
- **Stay local**: most open-source solutions either don't support Chinese, can't respond in 100 ms, or require a multi-GB model in memory.

PocketSearch proves that **"small-footprint on-device semantic search is practical"**:

| Metric | Value |
|---|---|
| Vector query | **2–3 ms** |
| End-to-end response | **~100 ms** |
| Network traffic | **0 bytes** |
| Integration effort | **3 APIs, ~30 lines of code** |

---

## Features

| Feature | Description |
|---|---|
| **Natural language search** | `sunset over the ocean with clouds`, `latte art on a cup of coffee` — write sentences, not keywords |
| **Hybrid query** | Visual semantics + time + geolocation in one pass: "buildings in Beijing last summer" |
| **Fully offline** | The engine has no network module — it is *architecturally incapable* of transmitting data |
| **Optional LLM rewrite** | Want smarter Chinese / colloquial understanding? Plug in any OpenAI-compatible endpoint (only query text is sent) |
| **Background indexing** | First-launch indexing runs in the background without blocking UI |
| **Lightweight integration** | `flutter pub get` + three APIs to embed into your own app |

---

## How It Works

```
User input: "colorful flowers in a garden"
              │
              ▼
     ┌───────────────┐     ┌─────────────┐     ┌──────────────┐
     │ MobileCLIP    │ ──▶ │ zvec        │ ──▶ │ Top-K Results │
     │ Text Encoder  │     │ HNSW+scalar │     │ (photo IDs)   │
     │ (~90 ms)      │     │ (2–3 ms)    │     │              │
     └───────────────┘     └─────────────┘     └──────────────┘
```

Two core components:

- **[MobileCLIP-S1](https://github.com/apple/ml-mobileclip)** — maps text and images into the same 512-dim embedding space
- **[zvec](https://github.com/zvec-ai/zvec-dart)** — on-device vector database with HNSW retrieval + scalar filtering in a single pass

First launch builds the index in background (~250 ms / photo). After that, search is instant.

---

## Performance

All numbers measured on **iPhone SE 3 (A15)** in release mode.

| Metric | Value |
|---|---|
| zvec query | **2–3 ms** |
| End-to-end search (incl. CLIP encode) | **90–120 ms** |
| Hybrid query (vector + 3 scalar filters) | **< 120 ms** |
| Single insert | < 1 ms |
| Full index (10K photos, background) | ~50 min |
| Memory footprint (10K vectors + HNSW) | **~40 MB** |

**Binary size breakdown (arm64, release APK):**

| Component | Size |
|---|---|
| zvec engine (`libzvec.so`) | ~49 MB |
| MNN runtime (`libmnn_c_api.so`) | ~3.5 MB |
| MobileCLIP image encoder (`.mnn`) | ~41 MB |
| MobileCLIP text encoder (`.mnn`) | ~121 MB |
| Total APK (single-arch arm64) | ~259 MB |

> The vector engine is never the bottleneck — 2–3 ms out of 100 ms total.

---

## Quick Start

### Prerequisites

- Flutter SDK ≥ 3.41 (Dart ≥ 3.11)
- Android device (API 24+) or iOS device (16+)
- MobileCLIP-S1 model files (see [Model Preparation](#model-preparation))

### Install & Run

```bash
git clone git@gitlab.alibaba-inc.com:xufeihong.xfh/PocketSearch.git
cd PocketSearch
flutter pub get
flutter run
```

### Model Preparation

```bash
pip install torch mobileclip onnx onnxruntime
python scripts/export_onnx.py     # Export ONNX
bash scripts/convert_mnn.sh        # Convert to MNN
```

Output goes to `assets/models/`:

- `mobileclip_s1_image_encoder.mnn`
- `mobileclip_s1_text_encoder.mnn`

Place the BPE vocabulary at `assets/tokenizer/bpe_vocab.json`.

### iOS First Build

Xcode workspace is not committed (contributors use their own signing). First time:

```bash
flutter create --platforms=ios --org ai.zvec --project-name zvec_photo_search .
cd ios && pod install && cd ..
open ios/Runner.xcworkspace   # Set your signing team, then build
```

### Demo Dataset

Real phone galleries are mostly WeChat screenshots and food-delivery vouchers — CLIP looks bad even when it's working perfectly. Use the curated [Unsplash Lite](https://unsplash.com/data/lite/latest) dataset:

```bash
# 1. Download Unsplash Lite ZIP, extract metadata to data/unsplash_lite/photos.csv000
# 2. Download 10K photos (~2 GB, idempotent)
pip install requests tqdm
python scripts/download_demo_dataset.py --count 10000

# 3. Push to device
bash scripts/push_demo_to_android.sh   # Android: adb push → /sdcard/DCIM/zvec_demo/
bash scripts/push_demo_to_ios.sh       # iOS: AppleScript → Photos.app → iCloud → iPhone
```

Quick smoke test without full download:

```bash
scripts/seed_demo_dataset.sh   # 220 photos, zero download
```

**Recommended demo queries** (consistently strong on Unsplash Lite):

- `sunset over the ocean`
- `neon lights of a downtown skyline`
- `latte art on a cup of coffee`
- `white cat sitting on a windowsill`
- `snowy mountain peak`

More queries in `assets/demo_queries.json` (20 queries / 8 categories / with expected hit counts).

---

## Project Structure

```
lib/
├── services/
│   ├── clip_service.dart         # MNN inference wrapper
│   ├── index_service.dart        # Background gallery indexing
│   ├── search_service.dart       # Search orchestration
│   ├── vector_store.dart         # zvec wrapper
│   ├── query_rewriter.dart       # Optional LLM query agent
│   └── settings_service.dart     # Preferences
└── ui/
    ├── home_page.dart            # Main search UI
    └── widgets/
        ├── photo_grid.dart       # Results grid
        ├── suggestion_chips.dart # Query suggestions
        └── photo_detail_page.dart# Full-screen preview + share
```

### Tech Stack

| Component | Role |
|---|---|
| [zvec](https://github.com/zvec-ai/zvec-dart) | On-device vector database (HNSW + scalar filtering) |
| [MNN](https://github.com/alibaba/MNN) | Mobile inference engine |
| MobileCLIP-S1 | Image/text embedding model |
| photo_manager | System gallery access |
| Flutter | Cross-platform UI |

---

## Optional: LLM Query Agent

MobileCLIP only understands short English phrases. It can't handle _"last summer"_ or _"in Beijing"_ (relative time / geo intent). When enabled, the LLM agent translates natural language into:

```json
{
  "visual": "people having dinner at a restaurant",
  "date_start": "2026-04-01",
  "date_end": "2026-05-01",
  "geo": { "lat_min": 22.1, "lat_max": 22.5, "lng_min": 113.5, "lng_max": 114.0 }
}
```

| Mode | Network | Use case |
|---|---|---|
| **Off** (default) | none | 100% offline, CLIP processes raw input |
| **Remote** | query text only | Any OpenAI-compatible endpoint (DashScope / DeepSeek / OpenAI / Ollama …) |

**Never uploaded**: photo pixels, thumbnails, vectors, photo_id, EXIF, or any gallery state.
Any error gracefully falls back to the original query — search is never blocked.

### Configuration

Settings → "LLM Query Agent":

| Field | Default | Notes |
|---|---|---|
| Base URL | `https://dashscope.aliyuncs.com/compatible-mode/v1` | Any OpenAI-compatible endpoint |
| API Key | (must be configured) | Stored in `shared_preferences` |
| Model | `qwen-turbo` | Pick something small and fast; temperature pinned to 0 |

### Compatible Endpoints

| Provider | Base URL | Suggested model |
|---|---|---|
| Aliyun DashScope | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-turbo` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| Together AI | `https://api.together.xyz/v1` | `Llama-3.2-3B-Instruct-Turbo` |
| Self-hosted Ollama | `http://<host>:11434/v1` | any installed chat model |

### Troubleshooting

| UI Message | Likely Cause |
|---|---|
| `HTTP 401` | API key is wrong or expired |
| `HTTP 404` | Base URL doesn't expose `/chat/completions` |
| `timeout` | Default 8s; adjust via `OpenAICompatibleQueryRewriter.timeout` |
| `empty response` | Model output blank — usually a model misconfiguration |

---

## Privacy

PocketSearch's offline guarantee is not a policy — it's an **architecture**:

- zvec is a pure C library with zero socket calls;
- CLIP inference runs on the local MNN runtime;
- The only possible network request is the explicitly-enabled LLM agent, which transmits only the user's search text.

> Not a policy. An architecture.

---

## Testing

```bash
flutter test test/                              # Unit tests (~64 cases)
flutter test integration_test/                  # On-device integration (20 cases, 2 files)
```

> First run requires `bash scripts/prepare_mnn_src.sh` to fetch MNN source.

---

## Roadmap

- [ ] Chinese-CLIP for native Chinese query support
- [ ] BM25 keyword index + RRF fusion for OCR/text queries
- [ ] On-device small LM agent (pending hardware catching up)
- [ ] Multi-modal memory (photos + notes in one collection)

---

## Contributing

Issues and PRs welcome. Before submitting:

1. `flutter analyze` passes with no warnings;
2. Changes to vector/search/index logic must include or update unit tests;
3. For large changes, open an Issue first to align on design.

---

## License

[Apache License 2.0](LICENSE)

## Acknowledgments

- [Apple ML Research](https://github.com/apple/ml-mobileclip) for open-sourcing MobileCLIP
- [Alibaba MNN](https://github.com/alibaba/MNN) for a high-quality mobile inference runtime
- [Unsplash](https://unsplash.com/data) for the public dataset that makes demos look great

---

<details>
<summary><h2>📖 中文版本</h2></summary>

## ✨ 这是什么

**PocketSearch** 是一款 **100% 离线** 的语义相册搜索 App。它把 CLIP 多模态嵌入模型和向量数据库直接装进手机，让你用自然语言去找照片：

> _"去年夏天在北京拍的建筑"_ — 一句话，三个意图，一次本地查询返回结果。

没有云端、没有网络、没有上传。**照片、向量、元数据，全程不出你的设备。**

---

## 🎯 为什么会有这个项目

iOS 和 Android 都不向第三方 App 开放语义搜索 API。Apple 内部有一套（驱动 Photos app 的搜索），但不开放；Android 则完全没有。于是出现了一个尴尬的现实：

- **想上云**：得把整个相册同步给某家公司的服务器；
- **想本地搜**：90% 的开源方案要么不支持中文、要么 100ms 跑不出来、要么需要常驻几个 GB 的模型。

PocketSearch 想证明 **"小而美的端侧语义搜索是可行的"**：

| 指标 | 数值 |
|---|---|
| ⚡ 向量查询 | **2–3 ms** |
| 📦 端到端响应 | **~100 ms** |
| 🔒 网络传输 | **0 字节** |
| 🧩 集成成本 | **3 个 API，~30 行代码** |

---

## 🌟 主要特性

| 特性 | 说明 |
|---|---|
| **自然语言搜索** | `sunset over the ocean with clouds`、`latte art on a cup of coffee` —— 写句子，不写关键字 |
| **混合查询** | 视觉语义 + 时间 + 地理位置，一次表达一次过滤 |
| **完全离线** | 引擎本身没有网络模块，从架构上就**没法**把数据送出去 |
| **可选 LLM 改写** | 想要更聪明的中文/口语理解？接一个 OpenAI 兼容端点即可，仅传查询文本 |
| **后台索引** | 首次启动后台建索引，不阻塞用户操作 |
| **轻量集成** | `flutter pub get` + 三个 API 即可嵌入到你自己的 App |

---

## 📊 性能

下表数据均在 **iPhone SE 3 (A15)** 上 release 模式实测。

| 指标 | 数值 |
|---|---|
| zvec 单次查询 | **2–3 ms** |
| 端到端搜索（含 CLIP 编码） | **90–120 ms** |
| 混合查询（向量 + 3 个标量过滤） | **< 120 ms** |
| 单条插入 | < 1 ms |
| 全量索引（10K 照片，后台） | ~50 min |
| 内存占用（10K 向量 + HNSW） | **~40 MB** |

**二进制体积明细（arm64, release APK）：**

| 组件 | 大小 |
|---|---|
| zvec 引擎 (`libzvec.so`) | ~49 MB |
| MNN 推理运行时 (`libmnn_c_api.so`) | ~3.5 MB |
| MobileCLIP 图像编码器 (`.mnn`) | ~41 MB |
| MobileCLIP 文本编码器 (`.mnn`) | ~121 MB |
| 总 APK（单架构 arm64） | ~259 MB |

> 向量引擎从来不是瓶颈 —— 100 ms 总耗时里只占 2–3 ms。

---

## 🚀 快速开始

### 环境要求

- Flutter SDK ≥ 3.41（Dart ≥ 3.11）
- Android 设备（API 24+）或 iOS 设备（16+）
- MobileCLIP-S1 模型文件（见 [模型准备](#model-preparation)）

### 安装与运行

```bash
git clone git@gitlab.alibaba-inc.com:xufeihong.xfh/PocketSearch.git
cd PocketSearch
flutter pub get
flutter run
```

### 模型准备

```bash
pip install torch mobileclip onnx onnxruntime
python scripts/export_onnx.py     # 导出 ONNX
bash scripts/convert_mnn.sh        # 转换为 MNN
```

产物落到 `assets/models/`：`mobileclip_s1_image_encoder.mnn` 与 `mobileclip_s1_text_encoder.mnn`。

BPE 词表放到 `assets/tokenizer/bpe_vocab.json`。

### 演示数据集

```bash
pip install requests tqdm
python scripts/download_demo_dataset.py --count 10000
bash scripts/push_demo_to_android.sh   # Android
bash scripts/push_demo_to_ios.sh       # iOS
```

快速跑通而不下整套：`scripts/seed_demo_dataset.sh`（220 张图，零下载）。

**推荐 demo 查询**：`sunset over the ocean` · `neon lights of a downtown skyline` · `latte art on a cup of coffee` · `white cat sitting on a windowsill` · `snowy mountain peak`

---

## 🤖 可选：LLM 查询代理

MobileCLIP 只懂英文短句。开启 LLM 代理后，口语化/中文/含时间地点意图的查询会被翻译成 CLIP 能理解的结构化 JSON。

| 模式 | 联网情况 | 适用场景 |
|---|---|---|
| **Off**（默认） | 无 | 100% 离线 |
| **Remote** | 仅传查询文本 | 任意 OpenAI 兼容端点 |

兼容端点：阿里 DashScope / OpenAI / DeepSeek / Together AI / 自建 Ollama。

---

## 🔒 隐私

PocketSearch 的离线性不靠"我们承诺不上传"，而是靠 **架构本身没有网络出口**。

> 不是政策。是架构。

---

## 🧪 测试

```bash
flutter test test/                              # 单元测试（~64 用例）
flutter test integration_test/                  # 端侧集成测试（20 用例，2 个文件）
```

---

## 📄 License

[Apache License 2.0](LICENSE) — 自由使用、修改、商用，请保留版权与许可声明。

</details>
