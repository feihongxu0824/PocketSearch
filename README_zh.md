<div align="center">

# PocketSearch

**用一句话描述它，在手机本地找到它。**

*口袋里的端侧个人数据检索层 —— 从相册开始。*

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)]()
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.41-02569B.svg?logo=flutter)]()
[![Engine](https://img.shields.io/badge/Zvec-on--device-success.svg)](https://github.com/alibaba/zvec)

[English](README.md) · [中文](README_zh.md)

![Demo](docs/assets/demo_search.gif)

</div>

---

PocketSearch 让你可以用自然语言描述一张照片，然后在本地相册里找到它，不依赖手动整理相册，也不需要云端往返。底层由 [Zvec](https://github.com/alibaba/zvec) 及其 [Dart/Flutter SDK](https://github.com/zvec-ai/zvec-dart) + [MobileCLIP-S1](https://github.com/apple/ml-mobileclip) 驱动，通过 [MNN](https://github.com/alibaba/MNN) 在设备本地运行。

## 🎯 项目愿景

手机里的个人数据被分散在相册、备忘录、邮件、短信、文件和第三方 app 里，而它们大多太敏感，不适合轻易离开设备。随着移动端 AI 助手能力越来越强，它们需要一个**本地检索层**可以直接查询，而不是云端往返。

PocketSearch 就是我们对这一层的回答。产品原则很简单：

- **本地优先**。索引、embedding、召回、排序全部在设备本地完成。默认链路零上传、零 socket 请求。
- **多数据源**。今天是相册；未来是备忘录、邮件、文件、截图 / OCR、第三方 app 数据。
- **人机双用**。既是给人用的搜索框，也是给端侧 agent 调用的结构化检索 API。

我们从**相册**开始，是因为它是大多数手机上体量最大、增长最快的个人数据集 —— 截图、票据、白板、聊天截屏。用户很少记得文件名或拍摄时间，他们记得的是"画面里有什么"。

## ⚡ 快速开始

> **环境要求**：Flutter ≥ 3.41、Xcode 15+（只要 iOS）、Android SDK（只要 Android）。
> 如果需要从源码转换模型，还需要安装 `uv`。

### 公共准备（iOS 和 Android 都需要）

```bash
git clone git@gitlab.alibaba-inc.com:xufeihong.xfh/PocketSearch.git
cd PocketSearch
flutter pub get
bash scripts/prepare_mnn_src.sh      # 下载 MNN 源码（约 89 MB，缓存在 ~/.cache/）
bash scripts/check_models.sh         # 检查必需的 MobileCLIP .mnn 模型文件
```

如果 `check_models.sh` 提示模型缺失，请先完成[模型准备](#模型准备仅当缺失时)再构建。
Flutter 构建也会显式引用这两个模型文件，因此模型缺失时会在构建阶段失败，而不是生成一个无法正常启动的 APK/IPA。

### Android

```bash
flutter build apk --release
flutter install --release -d <ANDROID_DEVICE_ID>
```

也可以使用 `adb` 安装生成的 APK：

```bash
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"   # macOS 默认 Android SDK 路径
adb install build/app/outputs/flutter-apk/app-release.apk
```

安装后打开 App、授予相册权限即可。

### iOS

iOS 的 Xcode project / workspace 不提交到仓库，需要先在本地生成：

```bash
flutter create --platforms=ios --org app --project-name pocketsearch .
cd ios && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install && cd ..
```

然后：

1. 在 Xcode 里添加你的 Apple ID：**Xcode → Settings → Accounts → "+"**
2. 打开生成的 workspace 并配置签名：
   ```bash
   open ios/Runner.xcworkspace
   ```
   在 Xcode 中：**Runner project → Signing & Capabilities → Team → 选择你的账号**
3. 连接 iPhone，选为目标设备，点击 **▶ Run**。
4. 首次在设备上启动时：**设置 → 通用 → VPN 与设备管理** → 信任开发者证书。

> 首次 Xcode 成功构建后，后续可以用 `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter run -d <DEVICE_ID> --release` 运行。查看设备 ID：`xcrun xctrace list devices`

### 模型准备（仅当缺失时）

模型二进制文件较大，不提交到 git。PocketSearch 运行前需要以下两个文件：

```text
assets/models/mobileclip_s1_image_encoder.mnn
assets/models/mobileclip_s1_text_encoder.mnn
```

如果你的分发包提供了预转换的 release assets，请下载到 `assets/models/`。否则，可以从 MobileCLIP-S1 重新导出。下面的命令使用 `uv`；如果本机还没有，可以先安装：`curl -LsSf https://astral.sh/uv/install.sh | sh`。如果网络较慢，可以按需替换 `--index-url` 镜像源。

```bash
curl -L -o /tmp/mobileclip_s1.pt \
  https://docs-assets.developer.apple.com/ml-research/datasets/mobileclip/mobileclip_s1.pt
python3 -m venv .venv
uv pip install --python .venv/bin/python \
  --index-url https://pypi.tuna.tsinghua.edu.cn/simple \
  torch torchvision timm open-clip-torch onnx onnxruntime MNN
uv pip install --python .venv/bin/python --no-deps \
  "mobileclip @ git+https://github.com/apple/ml-mobileclip.git"
.venv/bin/python scripts/export_onnx.py
PATH="$PWD/.venv/bin:$PATH" bash scripts/convert_mnn.sh
bash scripts/check_models.sh
```

### 演示数据集

```bash
bash scripts/seed_demo_dataset.sh   # 220 张精选照片，零下载
# 或者完整的 10K Unsplash Lite：
python scripts/download_demo_dataset.py --count 10000
bash scripts/push_demo_to_android.sh
```

---

## 🏗️ 架构

```
"sunset over the ocean"
        │
        ▼
┌──────────────┐     ┌────────────┐     ┌────────────┐
│ MobileCLIP   │ ──▶ │   Zvec     │ ──▶ │  Top-K     │
│ Text Encoder │     │ HNSW+scalar│     │  Results   │
│ (~117–130 ms)│     │ (~1 ms)    │     │            │
└──────────────┘     └────────────┘     └────────────┘
```

| 组件 | 职责 |
|---|---|
| [Zvec](https://github.com/alibaba/zvec) | 端侧检索引擎（向量索引 / 检索、scalar 过滤，并可继续承载混合检索）|
| [MNN](https://github.com/alibaba/MNN) | 移动端推理引擎 |
| MobileCLIP-S1 | 图像 / 文本 embedding（512 维）|

> 今天输入是照片、输出是排序后的结果列表。同一条 *encode → index → retrieve → fuse* 管道可以推广到备忘录、邮件、文件、截图 OCR。Zvec 在检索层位置不变，上游的编码器随数据源类型演进。

---

## 📊 性能

在小米 14 Ultra（Android 15）、正式构建版本、索引 `10,239` 张本地测试图片的环境下测量：

| 指标 | 数值 |
|---|---|
| 端到端搜索 | **117–131 ms** |
| Zvec 本地召回 | **~1 ms** |
| Zvec 索引文件 | **24.0 MB** |
| Zvec 索引内存增量 | **~37 MB** |
| App 整体内存占用 | **~875 MB** |
| 网络流量 | **0 字节** |

App 整体内存占用包含 MobileCLIP 图像 / 文本 encoder、MNN runtime、Flutter UI、解码图片和 Zvec 索引；其中 Zvec 索引自身带来的内存增量约为 **37 MB**。

---

## 🔒 隐私

离线保证不是一条隐私策略 —— 它是一个**架构选择**：Zvec 完全不含 socket 调用，CLIP 运行在本地 MNN runtime 上。唯一可选的联网路径是查询改写器（只发送查询文本，默认关闭）。

---

## 🗺️ 路线图

**Now（现在）— 相册。** 本地相册语义搜索、后台增量索引、混合查询（向量 + 时间 + 地理）、可选 LLM 查询改写（默认关闭）。

**Next（下一步）— 更多数据源。** 截图 OCR、备忘录、邮件、文件。BM25 关键词召回与向量召回融合。中文 CLIP。对外输出稳定的检索 API 表面，让端侧 agent 可调用。

**Later（远期）— 统一上下文。** 多数据源融合排序、端侧对结果集做摘要、可插拔 embedding 模型、查询时用自然语言表达的 scalar filter。

---

## 🧪 测试

```bash
flutter test test/                   # 单元测试（约 64 个）
flutter test integration_test/       # 真机集成测试（20 个）
```

---

## 📄 许可

[Apache License 2.0](LICENSE)
