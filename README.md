<div align="center">

# PocketSearch

**Describe it. Find it. On your phone, offline.**

口袋里的语义相册搜索 —— 用一句话，找回那张照片。

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)]()
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.10-02569B.svg?logo=flutter)]()
[![Engine](https://img.shields.io/badge/zvec-on--device-success.svg)](https://github.com/zvec-ai/zvec-dart)

![Demo](docs/assets/demo_search.gif)

</div>

---

## ✨ 这是什么

**PocketSearch** 是一款 **100% 离线** 的语义相册搜索 App。它把 CLIP 多模态嵌入模型和向量数据库直接装进手机，让你用自然语言去找照片：

> _"去年夏天在北京拍的建筑"_ — 一句话，三个意图，一次本地查询返回结果。

没有云端、没有网络、没有上传。**照片、向量、元数据，全程不出你的设备。**

---

## 🎯 为什么会有这个项目

iPhone 自带的相册搜索仅对自家 App 开放底层能力，第三方 App 只能拿到一份 EXIF 元数据。Android 这边则连这层能力都不存在。于是出现了一个尴尬的现实：

- **想上云**：得把整个相册同步给某家公司的服务器；
- **想本地搜**：90% 的开源方案要么不支持中文、要么 100ms 跑不出来、要么需要常驻几个 GB 的模型。

PocketSearch 想证明 **"小而美的端侧语义搜索是可行的"**：

| | |
|---|---|
| 🔋 引擎二进制 | **4 MB** |
| ⚡ 单次查询 | **2–3 ms** |
| 📦 端到端响应 | **~100 ms** |
| 🔒 网络传输 | **0 字节** |
| 🧩 集成成本 | **3 个 API，30 行代码** |

---

## 🌟 主要特性

| 特性 | 说明 |
|---|---|
| **自然语言搜索** | `sunset over the ocean with clouds`、`latte art on a cup of coffee` —— 写句子，不写关键字 |
| **混合查询** | 视觉语义 + 时间 + 地理位置，一次表达一次过滤："去年夏天在北京拍的建筑" |
| **完全离线** | 引擎本身没有网络模块，从架构上就**没法**把数据送出去 |
| **可选 LLM 改写** | 想要更聪明的中文/口语理解？接一个 OpenAI 兼容端点即可，仅传查询文本 |
| **后台索引** | 首次启动后台慢慢建索引，不阻塞用户操作 |
| **轻量集成** | `flutter pub get` + 三个 API 即可嵌入到你自己的 App |

---

## 🧠 工作原理

```
用户输入: "colorful flowers in a garden"
            │
            ▼
   ┌───────────────┐     ┌─────────────┐     ┌──────────────┐
   │ MobileCLIP    │ ──▶ │ zvec        │ ──▶ │ Top-K 结果    │
   │ Text Encoder  │     │ HNSW + 标量  │     │ (照片 ID/路径) │
   │ (~90 ms)      │     │ (2–3 ms)    │     │              │
   └───────────────┘     └─────────────┘     └──────────────┘
```

两块核心组件：

- **[MobileCLIP-S1](https://github.com/apple/ml-mobileclip)** —— 把文本与图片映射到同一个 512 维语义空间；
- **[zvec](https://github.com/zvec-ai/zvec-dart)** —— 端侧向量数据库，HNSW 检索 + 标量过滤合并到一次扫描。

首次启动会在后台为相册建索引（约 250 ms / 张），之后就是即时搜索。

---

## 📊 性能

下表数据均在 **iPhone SE 3 (A15)** —— 苹果在售最便宜的机型 —— 上 release 模式实测。

| 指标 | 数值 |
|---|---|
| zvec 单次查询 | **2–3 ms** |
| 端到端搜索（含 CLIP 编码） | **90–120 ms** |
| 混合查询（向量 + 3 个标量过滤） | **< 120 ms** |
| 单条插入 | < 1 ms |
| 全量索引（10K 照片，后台） | ~50 min |
| 引擎二进制 | **4 MB** |
| 内存占用（10K 向量 + HNSW） | **~40 MB** |

> 向量引擎从来不是瓶颈 —— 100 ms 总耗时里只占 2–3 ms。

---

## 🚀 快速开始

### 环境要求

- Flutter SDK ≥ 3.10
- Android 设备（API 24+）或 iOS 设备（15+）
- MobileCLIP-S1 模型文件（见下文 [模型准备](#模型准备)）

### 安装与运行

```bash
git clone https://github.com/your-org/pocketsearch.git
cd pocketsearch
flutter pub get
flutter run
```

### 模型准备

```bash
pip install torch mobileclip onnx onnxruntime
python scripts/export_onnx.py     # 导出 ONNX
bash scripts/convert_mnn.sh        # 转换为 MNN
```

产物会落到 `assets/models/`：

- `mobileclip_s1_image_encoder.mnn`
- `mobileclip_s1_text_encoder.mnn`

BPE 词表放到 `assets/tokenizer/bpe_vocab.json`。

### iOS 首次构建

为了不污染贡献者的签名配置，Xcode workspace 不入库。第一次构建：

```bash
flutter create --platforms=ios --org ai.zvec --project-name zvec_photo_search .
cd ios && pod install && cd ..
open ios/Runner.xcworkspace   # 设置签名 Team 后再构建
```

### 演示数据集

真实手机相册大多是微信截图、外卖券、文档扫描，CLIP 在这种语料上即使表现完美也"看上去很差"。建议用一份 [Unsplash Lite](https://unsplash.com/data/lite/latest) 精选数据集来体验：

```bash
# 1. 下载 Unsplash Lite ZIP，解压元数据到 data/unsplash_lite/photos.csv000
# 2. 下载 10K 张照片（~2 GB，幂等可重跑）
pip install requests tqdm
python scripts/download_demo_dataset.py --count 10000

# 3. 推到设备
bash scripts/push_demo_to_android.sh   # Android: adb push → /sdcard/DCIM/zvec_demo/
bash scripts/push_demo_to_ios.sh       # iOS: AppleScript → Photos.app → iCloud → iPhone
```

想先快速跑通而不下整套？

```bash
scripts/seed_demo_dataset.sh   # 220 张图，零下载
```

**推荐 demo 查询**（在 Unsplash Lite 子集上几乎不会翻车）：

- `sunset over the ocean`
- `neon lights of a downtown skyline`
- `latte art on a cup of coffee`
- `white cat sitting on a windowsill`
- `snowy mountain peak`

更多查询见 `assets/demo_queries.json`（20 条 / 8 类别 / 每条附预期命中数）。

---

## 🧩 项目结构

```
lib/
├── services/
│   ├── clip_service.dart         # MNN 推理封装
│   ├── index_service.dart        # 后台相册索引
│   ├── search_service.dart       # 搜索编排
│   ├── vector_store.dart         # zvec 封装
│   ├── query_rewriter.dart       # 可选 LLM 查询代理
│   └── settings_service.dart     # 偏好设置
└── ui/
    ├── home_page.dart            # 主搜索界面
    └── widgets/
        ├── photo_grid.dart       # 结果网格
        ├── suggestion_chips.dart # 查询建议
        └── photo_detail_page.dart# 全屏预览 + 分享
```

### 技术栈

| 组件 | 角色 |
|---|---|
| [zvec](https://github.com/zvec-ai/zvec-dart) | 端侧向量数据库（HNSW + 标量过滤） |
| [MNN](https://github.com/alibaba/MNN) | 移动端推理引擎 |
| MobileCLIP-S1 | 图文嵌入模型 |
| photo_manager | 系统相册访问 |
| Flutter | 跨平台 UI |

---

## 🤖 可选：LLM 查询代理

MobileCLIP 只懂英文短句，搞不定 _"去年夏天"_、_"在北京"_ 这类相对时间和地理意图。开启 LLM 代理后，自然语言会被翻译成：

```json
{
  "visual": "people having dinner at a restaurant",
  "date_start": "2026-04-01",
  "date_end": "2026-05-01",
  "geo": { "lat_min": 22.1, "lat_max": 22.5, "lng_min": 113.5, "lng_max": 114.0 }
}
```

| 模式 | 联网情况 | 适用场景 |
|---|---|---|
| **Off**（默认）| 无 | 100% 离线，CLIP 直接处理原始输入 |
| **Remote** | 仅传查询文本 | 任意 OpenAI 兼容端点（DashScope / DeepSeek / OpenAI / Ollama …） |

**永远不会上传**：照片像素、缩略图、向量、photo_id、EXIF 或任何相册状态。
任何错误都会优雅回退到原始查询，绝不阻断搜索。

### 配置

在 Settings → "LLM Query Agent" 填入以下字段：

| 字段 | 默认值 | 说明 |
|---|---|---|
| Base URL | `https://dashscope.aliyuncs.com/compatible-mode/v1` | 任意 OpenAI 兼容端点 |
| API Key | （需手动填写） | 存于 `shared_preferences` |
| Model | `qwen-turbo` | 选小而快的模型，temperature 固定为 0 |

### 兼容端点示例

| 服务商 | Base URL | 推荐模型 |
|---|---|---|
| 阿里 DashScope | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-turbo` |
| OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| DeepSeek | `https://api.deepseek.com/v1` | `deepseek-chat` |
| Together AI | `https://api.together.xyz/v1` | `Llama-3.2-3B-Instruct-Turbo` |
| 自建 Ollama | `http://<host>:11434/v1` | 任意已安装的 chat 模型 |

### 故障排查

| 界面提示 | 可能原因 |
|---|---|
| `HTTP 401` | API Key 错误或过期 |
| `HTTP 404` | Base URL 不对，未暴露 `/chat/completions` |
| `timeout` | 默认 8s 超时，可调 `OpenAICompatibleQueryRewriter.timeout` |
| `empty response` | 模型输出为空，通常是模型配置问题 |

---

## 🔒 隐私

PocketSearch 的离线性不靠"我们承诺不上传"，而是靠**架构本身没有网络出口**：

- zvec 引擎是一段没有任何 socket 调用的纯 C 库；
- CLIP 推理跑在本地的 MNN 运行时上；
- 唯一可能的网络请求来自显式开启的 LLM 代理，传输的也只是用户输入的搜索文本。

> 不是政策。是架构。

---

## 🧪 测试

```bash
flutter test test/                              # 单元测试（约 40 用例）
flutter test integration_test/smoke_test.dart   # 端侧集成测试（17 用例）
```

> 首次执行集成测试需先 `bash scripts/prepare_mnn_src.sh` 拉取 MNN 源码。

---

## 🗺️ Roadmap

- [ ] Chinese-CLIP：原生中文检索能力
- [ ] BM25 关键词索引 + RRF 融合，覆盖 OCR / 纯文字查询
- [ ] 端侧轻量 LM 代理（等硬件再往前走一步）
- [ ] 多模态记忆（照片 + 笔记同集合）

---

## 🤝 贡献

欢迎 Issue 与 PR。提交前请：

1. `flutter analyze` 无告警；
2. 涉及向量/搜索/索引逻辑的改动需附带或更新单测；
3. 大改动建议先开 Issue 对齐设计。

---

## 📄 License

[Apache License 2.0](LICENSE) — 自由使用、修改、商用，请保留版权与许可声明。

## 🙏 Acknowledgments

- [Apple ML Research](https://github.com/apple/ml-mobileclip) 开源 MobileCLIP；
- [Alibaba MNN](https://github.com/alibaba/MNN) 提供高质量的移动推理运行时；
- [Unsplash](https://unsplash.com/data) 的高质量公共数据集让 demo 更好看。
