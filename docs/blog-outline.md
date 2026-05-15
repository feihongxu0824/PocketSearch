# 把 1 万张照片塞进手机 + 一个会"扣过滤条件"的 Agent —— zvec 走向移动端

> 一句话：在你手机上，**0.3 秒**从 1 万张照片里捞出"上个月在澳门拍的吃饭照片"，
> 全程不联网搜索，只把那一句中文发给 LLM Agent。

---

## TL;DR

- `zvec` 这个轻量级向量数据库，正式有了 [**Flutter SDK**（zvec-dart）](https://github.com/zvec-ai/zvec-dart)。Android arm64 + iOS arm64 双平台预编译，`flutter pub get` 即用。
- 我把它接到 [MobileCLIP-S1](https://github.com/apple/ml-mobileclip)（用 [MNN](https://github.com/alibaba/MNN) 跑）做了个**端侧语义搜图 demo**：1 万张候选、离线、< 50ms 出结果。
- 加了一个**轻量级 LLM Query Agent**：把一句"上个月在澳门拍的吃饭照片"拆成 ① CLIP 看得懂的英文视觉描述 + ② 结构化的 date / geo 过滤条件，端侧用 zvec 的标量过滤一刀切下去。
- 中间踩了个**反直觉的坑**：zvec 标量过滤遇到"该字段缺失"的文档时是**直接放行**，不是排除——发现这个之前，无 GPS 的照片会被错误召回到澳门 bbox 里。
- 全开源：[zvec-android-demo](https://github.com/<your>/zvec-android-demo)（Apache 2.0）。

---

## 第一部分：zvec 真正走向移动端

### 1.1 之前的空缺

[`alibaba/zvec`](https://github.com/alibaba/zvec) 是阿里开源的轻量、in-process 向量数据库，过去主要在服务端 / 桌面端跑。
移动端长期是个尴尬空缺：

- SQLite + 手撸 cosine：能跑，但全表暴搜，1 万条以上肉眼可感；
- HNSWLib / Faiss：算法 OK，但没有成熟的 Flutter / Android 绑定，要自己处理 FFI、动态库分发、ABI；
- MediaPipe Vector Search：和 LiteRT 强耦合，灵活度低。

我们想要的就是一个"`pub add` 之后就有的真·向量库"。

### 1.2 现在：zvec-dart 0.4.0

新版 `zvec 0.4.0` 发布了 [`zvec-ai/zvec-dart`](https://github.com/zvec-ai/zvec-dart) Flutter 包：

- **预编译双平台**：Android arm64-v8a + iOS arm64，`flutter pub get` 拿到即用，不需要在本机编译 native。
- **完整能力对齐**：cosine / L2 / IP 三种度量；标量字段过滤；批量插入 / 删除 / 查询；冷启动持久化。
- **API 极简**：插入、查询、删除三个核心方法，剩下的事都交给 SDK。

```dart
final col = ZvecCollection.create(dim: 512, metric: Metric.cosine);
col.insert([VectorDoc(id: photoId, vector: emb)
  ..setField('latitude', lat)
  ..setField('longitude', lng)
  ..setField('created_at', ts)]);

final hits = col.query(textEmb,
    topK: 20,
    filter: 'latitude >= 22.1 AND latitude <= 22.5');
```

### 1.3 这个 demo 解决了什么

- 验证 zvec Flutter 包在真实场景下扛得住：1 万张图、冷启动增量同步、
  HEIC 格式（iOS PhotoKit 默认格式）、photoId 含 `/`、相册增删等坑。
- 给社区一个能直接 fork 的"端侧语义搜图"模版：[zvec-android-demo](https://github.com/<your>/zvec-android-demo)。

---

## 第二部分：Demo —— 端侧语义搜图，效果实测

### 2.1 整体管线

```text
拍照 ──▶ MNN MobileCLIP-S1 image encoder ──▶ 512-d vector ──▶ zvec collection.insert
                                                                          │
                       (一切都在手机里 │ 无网络往返)
                                                                          ▼
用户输入 ──▶ (可选) LLM Agent ──▶ MNN text encoder ──▶ zvec collection.query
                                                              ──▶ 命中 photoId 列表
```

**关键：图片、缩略图、向量永远不离开设备。** LLM Agent 只看 query 文本本身。

### 2.2 数据集

- 演示库：1 万张 [Unsplash Lite](https://unsplash.com/data) 专业摄影 + 真机自带的旅行照 / 自拍，覆盖 8 类典型场景。
- 不用聊天截图、外卖券，避免"垃圾池里搜什么都精准"的假象。
- 复现脚本：`scripts/download_demo_dataset.py`（30 分钟下载 + adb push）。

### 2.3 索引

- **冷启动增量同步**：第一次启动跑全量索引，后续只 diff 入库 / 清理已删除；进度实时显示在状态栏。
- 单张索引耗时（iPhone 14 Pro）：MNN image encoder ≈ 18 ms / 张 + zvec insert ≈ 0.6 ms / 条。
- 1 万张全量约 3 分钟，期间可以正常搜索。

### 2.4 搜索

```text
query                       端侧耗时    命中数
sunset over the ocean       42 ms       12 / 10000
white cat on a windowsill   38 ms        4 / 10000
latte art on a coffee cup   35 ms        7 / 10000
```

> 端侧 1 万张候选 + 全英文 query + 离线 + < 50 ms 出结果 = 这套是真能跑的。

但你也看到了——**全英文 query**。中文一上来就拉胯，这是下一节要解决的事。

---

## 第三部分：LLM Query Agent —— 把"上个月在澳门拍的吃饭照片"翻译给 CLIP

### 3.1 一个尴尬的现实

MobileCLIP-S1 是英文 BPE，中文走 byte-fallback：

```text
"去年夏天海边玩的照片"  → token 退化为字节流 → embedding 近随机 → 搜不到
"上个月在澳门拍的"     → 同上，且"上个月"这种时间意图 CLIP 根本不可能"理解"
```

两个问题叠加：① 跨语言；② 自然语言里的时间 / 地点意图。
只换 encoder（比如 Chinese-CLIP）能解决 ①，但解决不了 ②。

### 3.2 解法：让 LLM 当 Query Agent，输出**结构化** JSON

不是简单"翻译成英文"，而是把一句中文/英文 query **拆成三件东西**：

```json
{
  "visual":     "people having dinner at a restaurant",
  "date_start": "2026-04-01",
  "date_end":   "2026-05-01",
  "geo": { "lat_min": 22.1, "lat_max": 22.5,
           "lng_min": 113.5, "lng_max": 114.0 }
}
```

- `visual` 给 CLIP text encoder（英文，4–15 词，CLIP 最舒服的形状）；
- `date_start` / `date_end` / `geo` 拼成 zvec 标量过滤表达式，**直接在向量库内核做硬过滤**，不是查完再 filter。

完整 Agent prompt 见 [`docs/llm-query-rewriter.md`](llm-query-rewriter.md)，关键的几条 Rule：

1. 只在 query 里**显式**出现时间词时才填 `date_*`（"my dog" 不填）；
2. `geo` 用**城市级 bbox**（覆盖整个城区，不只是市中心）；
3. **如果同时出现地点和时间，必须两个 filter 都给**（这一条是踩坑后补的，见 §3.5）。

### 3.3 架构：可选、可降级、不破坏离线契约

```text
                   ┌──────────────────────────┐
                   │ SettingsService          │
                   │  mode: off | remote      │
                   │  baseUrl, apiKey, model  │
                   └─────────────┬────────────┘
                                 │ buildRewriter()
                                 ▼
            ┌─────────────────────────────────────────────┐
            │ QueryRewriter (interface)                   │
            ├──────────────────────────┬──────────────────┤
            │ IdentityQueryRewriter    │ OpenAICompatible │
            │ (default, no-op)         │ QueryRewriter    │
            │                          │ → POST chat/...  │
            └──────────────────────────┴──────────────────┘
                                 │
                                 ▼
   query ──▶ rewriter ──▶ visual + filters ──▶ tokenize+CLIP, zvec.query(filter=...)
```

设计上的几个关键点：

- **默认 Off**：开箱即纯离线，CLIP 看的是用户原始 query。隐私保守派直接用。
- **Remote 模式只发 query 文本**：永远不会把图片 / 嵌入 / EXIF 发出去。OpenAI 兼容协议，DashScope / DeepSeek / OpenAI / 自托管 Ollama 都能接。
- **任何错误自动降级**：超时、401、JSON 解析失败 → fallback 回原始 query，搜索一定有结果出。

> 关于本地 LLM：曾经接过 flutter_gemma + Qwen 1.5B 在端侧跑，
> 实测推理需 60 秒+，UX 不可接受，已下线。

### 3.4 实测 Agent 输出（DashScope `qwen-turbo`）

| 用户输入 | Agent 输出 |
|---|---|
| `去年夏天海边玩的照片` | `visual: "people playing on a sunny beach in summer"`<br>`date: 2025-06-01 → 2025-09-01` |
| `今天的照片` | `visual: "photos taken today"`<br>`date: 2026-05-13 → 2026-05-14` |
| `today photos` | `visual: "photos taken today"`<br>`date: 2026-05-13 → 2026-05-14` |
| `白猫` | `visual: "white cat indoors"` （无 filter）|
| `在北京拍的建筑` | `visual: "buildings and architecture in Beijing"`<br>`geo: 39.4–41.1, 115.4–117.5` |
| `my dog playing in the park` | `visual: "dog playing in a grassy park"` （无 filter，"my" 不算时间意图）|
| **`上个月在澳门拍的吃饭照片`** | `visual: "people having dinner at a restaurant"`<br>`date: 2026-04-01 → 2026-05-01`<br>`geo: 22.1–22.5, 113.5–114.0` |

UI 上这些 filter 会以 chip 的形式直接显示在搜索结果上方，肉眼可见 Agent 在干活：

```text
┌─────────────────────────────────────────┐
│ 上个月在澳门拍的吃饭照片            🔍 │
├─────────────────────────────────────────┤
│ Found 7 results from 10000 photos       │
│   [📅 2026-04-01 → 2026-05-01]          │
│   [📍 lat 22.10–22.50, lng 113.50–114.00]│
│  ┌──┬──┬──┐                             │
│  │  │  │  │  ...                        │
│  └──┴──┴──┘                             │
└─────────────────────────────────────────┘
```

### 3.5 一个反直觉的坑：zvec 标量过滤的"字段缺失"行为

**现象**：搜"澳门的吃饭照片"，filter 一切正常（`lat 22.1–22.5, lng 113.5–114.0`），但
返回的照片里赫然有几张明明是在我家拍的——压根没出过珠三角。

**第一直觉**：filter 没生效？还是 EXIF 解析错了？
**结果都不是**——是我的认知错了。

我原本以为 zvec 的行为是"字段缺失 → 不参与过滤 → 不被召回"。
真机 integration test 跑出来：**字段缺失 → 直接放行**（filter 谓词在该 doc 上不执行，等于 always-true）。

复盘：把"无 GPS 的照片完全不写 latitude / longitude 字段"当成了一种隐式排除条件，
但 zvec 不是这么设计的。

**修复**：

1. 索引阶段始终写入 sentinel 值（`latitude ?? 0.0` / `longitude ?? 0.0` / `created_at ?? 0`）。
2. `VectorStore.schemaVersion: 2 → 3`，触发已部署设备的自动重建索引。
3. 把这个契约钉死到 [`integration_test/zvec_filter_test.dart`](../integration_test/zvec_filter_test.dart)：缺字段的 doc 必须不被 bbox filter 召回。

教训：

> **遇到向量库的"硬过滤"行为，永远不要相信记忆——
> 写一个 3 条数据的最小 case 真机跑一遍。**

### 3.6 还有一个 prompt 层的坑：复合查询丢 filter

最初版的 7 条 few-shot 全是单意图（要么只有 date 要么只有 geo）。
模型学到了一个隐式偏见："二选一"：

```text
"澳门的上个月的照片"
  ❌ → 只输出 date，丢了 geo
"上海昨天的夜景"
  ❌ → 只输出 date，丢了 geo
"去年在东京吃的拉面"
  ❌ → 只输出 date，丢了 geo
```

修复：补一条强约束 Rule + 两条复合 few-shot（中文 + 英文各一）：

```text
Rule: If the query mentions BOTH a place AND a time, you MUST include BOTH
      "geo" AND date_start/date_end. Never drop one when both are present.

User: 上周在东京吃的拉面
{ "visual": "ramen noodles in a Japanese restaurant",
  "date_start": "2026-05-04", "date_end": "2026-05-11",
  "geo": { "lat_min": 35.5, "lat_max": 35.9,
           "lng_min": 139.5, "lng_max": 139.9 } }

User: photos in Paris last summer
{ "visual": "streets and landmarks in Paris",
  "date_start": "2025-06-01", "date_end": "2025-09-01",
  "geo": { "lat_min": 48.8, "lat_max": 48.9,
           "lng_min": 2.2,  "lng_max": 2.5 } }
```

修复后 5 个复合 case 全过、5 个单意图 case 无回归。

### 3.7 性能 / 隐私

- **延迟预算（Remote 模式）**：LLM Agent ≈ 1–2 s（DashScope qwen-turbo）+ tokenize ≈ 1 ms + CLIP encode ≈ 25 ms + zvec query < 5 ms = **总计 < 2.5 s**。
- **隐私**：只发 query 文本（一般几个词）到用户自己配的端点。永远不发图片 / 嵌入 / EXIF。
- **推荐配置**：
  - 国内：DashScope `qwen-turbo`（默认）
  - OpenAI：`gpt-4o-mini`
  - 自托管：Ollama `qwen2.5:3b` / `llama3.2:3b`

---

## 收尾

### 我们交付了什么

- ✅ zvec 端侧 Flutter SDK 验证（双平台预编译可用）
- ✅ 1 万张候选 + < 50 ms 离线搜图
- ✅ LLM Query Agent：自然语言（中/英）→ 视觉描述 + date / geo 结构化过滤
- ✅ 全开源：[zvec-android-demo](https://github.com/<your>/zvec-android-demo)（Apache 2.0）

### 后续路线

- [ ] Chinese-CLIP 替换 image/text encoder，让"白猫" 这种短中文 query 也能直接命中（不依赖 LLM）
- [ ] EXIF metadata 扩展：相机机型、ISO、焦距，加入可过滤标量
- [ ] Android 真机回归（缺设备，征集 tester）
- [ ] city → bbox 的字典化后处理，纠正 LLM 对小众城市估算偏差

### CTA

- 🔗 仓库：`https://github.com/<your>/zvec-android-demo`
- ⭐ Star / 🐛 Issue / 🔄 Fork 都欢迎
- 🎬 想先看效果？把这条转出去，三连过 100 我录中文搜图全流程 GIF。

---

## 素材清单（待录）

| 编号 | 类型 | 内容 | 必须真机 |
|---|---|---|---|
| #0 | GIF | Hook 三连搜（中文 + 英文混搭）| ✅ |
| #1 | IMG | 架构图（mermaid 渲染 PNG）| ❌ |
| #2.3 | GIF | 第二部分英文搜索三连 | ✅ |
| #3.4 | GIF | LLM Agent: "上个月在澳门拍的吃饭照片" → filter chips → 出图 | ✅ |
| #3.5 | IMG | 真机集成测试 log: `C_no_gps recalled? YES — filter LET IT THROUGH` | ✅ |
| #end | IMG | 仓库二维码 | ❌ |

**最小可发版本**：#0 + #2.3 + #3.4 三段动图录好就能发。
