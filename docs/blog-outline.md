# 都 2026 年了，iPhone 还不会语义搜图？集成 Zvec 轻松搞定

> **TL;DR**：用 zvec Flutter SDK + MobileCLIP，几行 Dart 代码给手机相册装上端侧语义搜图。
> 1 万张照片、全程离线、查询几十毫秒出结果。本文是一次完整的真机接入实战记录，
> 顺带把接入工时、包体积、内存这些"到底贵不贵"的数字摆出来。

---

## 0. 先看效果

<!-- GIF #0：三连搜（白猫 / 拉花咖啡 / 上个月在澳门拍的吃饭照片）—— 真机录屏 -->

> 上面这段 GIF 全程在 iPhone 上跑、未联网搜索（LLM 改写那一步只发了一句中文，没发任何照片）。
> 1 万张候选库里第三句中文的命中结果，从输入到出图走了不到 3 秒。

---

## 1. iPhone 图库的搜索，到底能干什么、不能干什么？

先把现状讲清楚——不踩 Apple，只描述边界。

### 1.1 老能力：标签 + 时间 + 地点 + 人脸（一直就有）

iPhone 自带相册（Photos）有一套不错的 on-device 视觉能力：

- **预定义标签搜索**：搜「狗」、「海滩」、「食物」能命中——靠 Apple 的端侧视觉分类，标签集是封闭的；
- **时间筛选**：左滑右滑切月份、按年份回顾；
- **地点聚类**：相册里能按城市看拍摄地，可以筛选；
- **人物识别**：人脸聚类，命名后可以搜。

这一层做得已经很好了。

### 1.2 新能力：Apple Intelligence Photos 自然语言搜索（iOS 18.1+）

2024 年下半年 Apple Intelligence 上线之后，Photos 多了两件事：

- **自然语言搜索**：搜索框可以直接输入一句话，比如 *a dog at the beach*，能命中相关照片；
- **Enhanced Visual Search**：地标 / POI 识别（图片哈希会上传到 Apple 服务器做匹配，默认开启可关闭）。

听起来很美好——但用上之前有四道门槛：

| 门槛 | 现状（截至 2026-05）|
|---|---|
| **设备** | 仅 iPhone 16 全系 + iPhone 15 Pro/Pro Max；iPhone 15 普通版 / 14 / 13 全部用不了 |
| **地区** | 国行 Apple Intelligence 2025-Q2 才正式开放；早期英文优先，简体中文随后跟上 |
| **能力强度** | 简单描述能命中，但**复合查询 / 抽象修饰 / 长中文**仍然容易退化成关键词搜——业内评价普遍是"不错但不够强" |
| **API 开放** | Apple Intelligence Photos 是 **Photos.app 独占**，**没有任何 API 暴露给第三方 App** |

### 1.3 但你做的 App，这些一行也用不上

注意上表最后一行——这才是这篇文章真正的破题点。

**作为 iPhone 用户**，部分人在部分时候能用上 Apple 自家相册的语义搜图；
**作为 iPhone 开发者**，无论你做的是相册类、笔记类、家庭存储类还是文档管理类 App，
你想给自己的图片库加自然语言搜索——Apple 这一整套能力**一行都用不上**。

你能调用的只有这些：

- **PhotoKit**：返回缩略图 / 原图 / EXIF，**不附带 Apple 打的语义标签**；
- **Vision framework**：物体检测、文字识别、人脸框可以做，**不暴露 Apple 内部用的视觉嵌入向量**；
- **Foundation Models framework**（2025-09 上线）：on-device **文本生成**模型，不是视觉检索接口。

所以这篇文章里说的「iPhone 还不会语义搜图」，准确意思是——
**作为一个开放的 App 平台，iPhone 上还没有现成的语义搜图能力可以拿来就用。**
你的 App 想要这个能力，要么自带模型自己做端侧检索，要么走云端 API 把图片传出去。
本文要证明的事就一件：前者的成本，比想象中低得多。

### 1.4 三个 query 直观对比

| Query | iPhone Photos<br>（含 Apple Intelligence）| 第三方 App<br>（你能做的）| zvec 端侧 demo |
|---|---|---|---|
| 「白猫」 | ✅ 标签命中 | ❌ 没有标签数据可用 | ✅ CLIP 直接懂 |
| 「拉花咖啡」 | ⚠️ 部分（食物 / 饮料标签太粗）| ❌ | ✅ CLIP 接住开放词汇 |
| 「圣诞节戴红色圣诞帽的合影」 | ⚠️ 简单描述能命中部分，复合属性不稳 | ❌ | ✅ CLIP 接住属性组合 |
| 「上个月在澳门拍的吃饭照片」 | ⚠️ 时间 / 地点拆得出，三层一起经常翻车 | ❌ | ✅ 视觉 / 时间 / 地点三层一刀切 |

这一节的结论：**Apple 自家 App 内已经做到一部分；你想做的 App 想做到，得自己接一套。**
那我们来看看怎么用 zvec 把这一层补上。

---

## 2. 接进来：zvec Flutter SDK 几行 Dart 代码搞定

这一节的目标只有一个：让你看到接入成本到底有多低。

### 2.1 一张图说清整条管线

```text
拍照 ──▶ MNN MobileCLIP-S1 image encoder ──▶ 512-d vector ──▶ zvec collection.insert
                                                                          │
                       (一切都在手机里 │ 无网络往返)
                                                                          ▼
用户输入 ──▶ (可选) LLM Agent ──▶ MNN text encoder ──▶ zvec collection.query
                                                              ──▶ 命中 photoId 列表
```

图片、缩略图、向量、EXIF 永远不离开设备。LLM Agent（可选）只看那一句 query 文本。

### 2.2 三个 API 看完就会用

`pubspec.yaml` 里加一行：

```yaml
dependencies:
  zvec: ^0.4.0   # Android arm64 + iOS arm64 双平台预编译，flutter pub get 即用
```

剩下的事真的就只有三个方法。

**建库**：

```dart
final schema = CollectionSchema(name: 'photo_embeddings', fields: [
  VectorSchema('embedding', 512, indexParams: HnswIndexParams()),
  FieldSchema(name: 'photo_id',   dataType: DataType.string),
  FieldSchema(name: 'created_at', dataType: DataType.int64),
  FieldSchema(name: 'latitude',   dataType: DataType.float64),
  FieldSchema(name: 'longitude',  dataType: DataType.float64),
]);
final col = Collection.createAndOpen(dbPath, schema);
```

**写入**（一张照片 = 一条 doc）：

```dart
final doc = Doc(id: photoId)
  ..setVector('embedding', clipEmbedding)   // Float32List(512)
  ..setField('photo_id',   photoId)
  ..setField('created_at', exifTimestamp)
  ..setField('latitude',   gpsLat)
  ..setField('longitude',  gpsLng);
col.insert([doc]);
```

**查询**（向量近邻 + 标量过滤一刀切）：

```dart
final hits = col.query(VectorQuery(
  fieldName: 'embedding',
  vector: textEmbedding,
  topk: 20,
  filter: 'created_at >= 1743436800000 AND created_at < 1746115200000 '
          'AND latitude  >= 22.1 AND latitude  <= 22.5 '
          'AND longitude >= 113.5 AND longitude <= 114.0',
));
```

就这些。不需要写 SQL、不需要管索引重建、不需要处理 ABI 分发——`flutter pub get` 之后这些都被 SDK 兜走了。

### 2.3 实测数字（iPhone 14 Pro，1 万张候选）

| 指标 | 数值 |
|---|---|
| 单张图片索引（MNN encode + zvec insert） | ≈ **18 ms + 0.6 ms** |
| 1 万张全量索引（首次冷启动）| ≈ **3 分钟**（期间不阻塞 UI） |
| 单次查询（CLIP text encode + zvec query）| **30–50 ms** |
| 包体积净增（zvec + MNN + MobileCLIP-S1 模型）| **≈ 90 MB**（其中模型权重 80 MB）|
| 索引常驻内存峰值（1 万向量 + HNSW）| **≈ 35 MB** |

> 一句话总结：**索引一次性、查询毫秒级、包体积主要花在模型权重上。**

---

## 3. zvec 真正出彩的地方：向量 + 标量过滤一体化

到目前为止你看到的还只是"端侧 CLIP 检索"。
这一节才是 zvec 最值得讲的地方——也是为什么它特别适合"自然语言 + EXIF 元数据"这类场景。

### 3.1 一句中文里其实有三个意图

回到第 1 节那个例子：

> *上个月在澳门拍的吃饭照片*

拆开看是三层：

| 意图 | 类型 | 适合的工具 |
|---|---|---|
| 「吃饭照片」 | 开放视觉描述 | CLIP 向量相似度 |
| 「上个月」 | 结构化时间区间 | EXIF `created_at` 范围过滤 |
| 「澳门」 | 结构化地理范围 | EXIF `lat/lng` bbox 过滤 |

如果分两步——先全库 CLIP 搜 top-1000，再 Dart 层 for-loop 过滤——那 1 万张数据下你会得到一个肉眼可感的延迟（CLIP 评分本身在 HNSW 之外做完整 10000 次比较是几十 ms 起）。

zvec 的做法是**让标量过滤在引擎内核里就生效**：HNSW 在遍历向量时直接跳过不满足 filter 的 doc，过滤和检索是一次性完成的。这是它在端侧能做到「复合查询 < 50ms」的根本原因。

### 3.2 让 LLM 当翻译官，把中文拆成 zvec 能消费的格式

CLIP 的 text encoder 是英文 BPE，中文走 byte-fallback 几乎搜不出东西；它也压根不理解「上个月」「澳门」这种结构化意图。所以中间塞一个轻量级 LLM Agent，专职做翻译：

```json
{
  "visual":     "people having dinner at a restaurant",
  "date_start": "2026-04-01",
  "date_end":   "2026-05-01",
  "geo": { "lat_min": 22.1, "lat_max": 22.5,
           "lng_min": 113.5, "lng_max": 114.0 }
}
```

- `visual` → 喂给 CLIP text encoder（英文、4–15 词，CLIP 最舒服的形状）；
- `date_*` / `geo` → 拼成 zvec filter 表达式直接进引擎；
- 结构化拒绝 / 错误 / 超时 → **自动降级**回原始 query 直接搜，永远不会"搜不出来"。

完整 prompt 在 [`docs/llm-query-rewriter.md`](llm-query-rewriter.md)。模式上提供两档：

- **Off**（默认）：纯离线，CLIP 直接吃用户原文。隐私保守派直接用。
- **Remote**：用户自己配 OpenAI 兼容端点（DashScope / DeepSeek / OpenAI / 自托管 Ollama 都行），**只发 query 文本本身**——图片、向量、EXIF 一个字节都不外传。

### 3.3 实测 Agent 输出（DashScope `qwen-turbo`，每次 ≈ 1–2 s）

| 用户输入 | Agent 输出 |
|---|---|
| `白猫` | `visual: "white cat indoors"` （无 filter）|
| `my dog playing in the park` | `visual: "dog playing in a grassy park"` （"my" 不算时间意图，正确不填 date）|
| `今天的照片` | `visual: "photos taken today"` + `date: 2026-05-13 → 2026-05-14` |
| `去年夏天海边玩的照片` | `visual: "people playing on a sunny beach"` + `date: 2025-06-01 → 2025-09-01` |
| `在北京拍的建筑` | `visual: "buildings and architecture in Beijing"` + `geo: 39.4–41.1, 115.4–117.5` |
| **`上个月在澳门拍的吃饭照片`** | `visual: "people having dinner at a restaurant"` + `date: 2026-04-01 → 2026-05-01` + `geo: 22.1–22.5, 113.5–114.0` |

UI 上这些 filter 会以 chip 的形式贴在结果上方，肉眼可见 Agent 在干活：

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

### 3.4 真机演示

<!-- GIF #3：在 iPhone 上输入 `上个月在澳门拍的吃饭照片`，
     filter chip 同时亮 📅 和 📍，结果区只剩 7 张澳门 / 餐厅照片 -->

---

## 4. 成本盘点：到底贵不贵

### 4.1 集成成本

| 项 | 工时 |
|---|---|
| `pubspec.yaml` 加一行 + `flutter pub get` | < 1 分钟 |
| 写一个 `VectorStore` 包装类（建库 / 增删改查 + sentinel 兜底）| ≈ 30 行有效代码，**< 1 小时** |
| 接 MNN / MobileCLIP-S1（image / text 两个 encoder）| ≈ 半天（主要在熟悉 MNN Flutter 绑定）|
| 集成 LLM Agent（OpenAI 兼容协议 + JSON schema 校验 + 降级）| ≈ 半天 |

总共 **一个工作日** 能从零跑出 demo。最贵的反而是上传 MNN 模型权重和调 prompt，zvec 那一层基本没花时间。

### 4.2 运行时成本

| 维度 | 数值 |
|---|---|
| 包体积净增 | **≈ 90 MB**（zvec native ≈ 4 MB，MobileCLIP-S1 模型权重 ≈ 80 MB，MNN 运行时 ≈ 5 MB） |
| 索引常驻内存（1 万向量 + HNSW）| **≈ 35 MB** |
| 全量索引耗时（1 万张）| **≈ 3 分钟**（期间 UI 可正常使用，可暂停）|
| 单次查询耗时 | **30–50 ms**（CLIP text encode + zvec HNSW 检索）|
| LLM Agent 端到端（Off / Remote）| **0 ms / 1–2 s**（Remote 用户自带 API key，token 成本由用户承担）|
| 设备发热 | 索引阶段中等（持续 CLIP encode），查询阶段无感 |

包体积大头是 CLIP 模型权重，不是 zvec。zvec 本身的 native 二进制只有 4 MB 左右。

### 4.3 心智成本

| 概念 | 你需要知道的 |
|---|---|
| API 数量 | **3 个核心方法**（create / insert / query）|
| Filter 语法 | 类 SQL `WHERE`，支持 `AND / OR / >= / <= / =`，会写 SQL 就会写 |
| Schema 演进 | 加字段 = bump `schemaVersion` + 重建索引（demo 里就这么干的）|

**结论：zvec 这一层的接入和运行成本都不贵。** 真正花钱的是 CLIP 模型权重（80 MB）和 LLM Agent 调用（如果你启用了 Remote 模式，按 token 计费由用户掏钱包，App 本身不烧钱）。

---

## 5. 局限和后续

不藏着，也不许诺没把握的事：

- **只验证了 iPhone 真机**：Android 那边代码全跑通、单元测试全过，但缺真机回归——征集 Android 测试同学。
- **CLIP 中文短 query 还得依赖 LLM**：「白猫」直接喂 CLIP 中文走 byte-fallback 命中率低，Roadmap 上是替换成 Chinese-CLIP，让短中文也能不依赖 LLM 直接走。
- **LLM 对小众城市的 bbox 估算偏差**：模型给的经纬度框对一线城市基本对得上，对县级市会偏。后续会加一个 city → bbox 字典做后处理纠正。
- **EXIF 元数据维度还少**：目前只用了时间和 GPS，相机机型、ISO、焦距这些可过滤标量都还没接上——zvec 的 schema 加字段成本极低，剩下的只是产品决策。

---

## 6. 展望：这条路还能再走两步

### 6.1 图库搜索本身：从两路召回走到三路召回

这次 demo 只做了两路：**CLIP 稠密向量** + **EXIF 标量过滤**。
现代搜索引擎的标配是三路融合，第三路——**关键词倒排（lexical / BM25）**——现在是缺的。

| 召回路 | 本次 demo | 它擅长但现在走不通的 query |
|---|---|---|
| 稠密向量（CLIP）| ✅ | — |
| 标量过滤（时间 / 地点 / 机型）| ✅ | — |
| 关键词倒排 | ❌ | 「iPhone 14 Pro 发布会照片」、「菜单上写了米其林那家」、OCR 文字、人名 / 品牌 / 型号 |

入场代价也不大：SQLite FTS5 / Tantivy 这类轻量级倒排索引与 zvec 并行打分，
后面加一层 RRF（Reciprocal Rank Fusion）做融合、上层还可以再接一个 cross-encoder reranker——
这是在不依赖外部联网的前提下、把召回质量推到接近 production-grade 级别的一个合理下一步。

### 6.2 端侧语义能力的下一站：知识库 / Memory

图库只是这套组合（端侧 embedding + 端侧向量库）的第一个落点。同样的 stack 可以挪到：

- **端侧个人知识库**：本地 Markdown / Obsidian / Notion / PDF / Email 的语义检索；隐私敏感的法律 / 医疗 / 财务文档（不能上云）。本地笔记生态现在已经很成熟，差的恰恰是一个端侧语义层把它们串起来。
- **Agent / LLM Memory**：ChatBot 个人长期记忆（「上周我们聊到的那个项目」）、Agent 任务历史回溯、端侧版的 Mem0 / Letta——不依赖 OpenAI / Pinecone，不担心账号或服务变动让历史记忆丢失。
- **多模态 Memory**：同一个 zvec collection 同时存图片向量和文本向量（两个 vector field），「那次旅行」一句话同时命中当时拍的照片和写的日记。

这些场景的共同前提只有三条：

1. 数据不能上云（隐私 / 法规 / 产品坚持）；
2. 模型在端侧能塞下（CLIP / MiniLM / Gemma-3n 这个量级现在都能）；
3. 检索延迟要低于网络往返（Wi-Fi 不总在 / 地铁 / 跨国 / 高铁）。

图库这三条都满足，下一波最有戏的是个人知识库。zvec 在这个组合里做的事其实很纯粹——
把「端侧能跑的向量索引」这件事做到几行 Dart 就能用上，最下面这一层拉低了，上面的应用层就更容易出活。

---

## 7. 仓库 + CTA

- 🔗 **Demo 仓库（Apache 2.0，欢迎 fork）**：[zvec-android-demo](https://github.com/<your>/zvec-android-demo)
- 📦 **zvec Flutter SDK**：[zvec-ai/zvec-dart](https://github.com/zvec-ai/zvec-dart)
- 📦 **zvec 内核**：[alibaba/zvec](https://github.com/alibaba/zvec)
- 📝 **开发过程中的两个工程坑复盘**：[docs/dev-notes.md](dev-notes.md)（只推荐给要同样接入 zvec / LLM Agent 的开发者看）

如果你也想给自己的 Flutter App 加端侧语义搜图：

1. 看本文 §2 三个 API；
2. clone demo 仓库照着改 `VectorStore` 那 100 行代码；
3. 模型选 MobileCLIP-S1（80 MB）或 Chinese-CLIP（你来挑）；
4. 想要中文复合查询，再接一个 LLM Agent（OpenAI 兼容协议都能跑）。

⭐ Star / 🐛 Issue / 🔄 Fork 都欢迎。
🎬 想看完整中文搜图全流程 GIF？转发这条到 100 我录详细版。

---

## 素材清单（待录）

| 编号 | 类型 | 内容 | 必须真机 |
|---|---|---|---|
| #0 | GIF | Hook 三连搜（白猫 / 拉花咖啡 / 上个月在澳门拍的吃饭照片）| ✅ |
| #1 | IMG | 架构图（mermaid 渲染 PNG）| ❌ |
| #1.3 | IMG | iPhone 自带相册 vs zvec demo 三句对比截图 | ✅ |
| #3 | GIF | LLM Agent 把中文拆成 visual + filter，UI chip 同时亮 📅+📍 | ✅ |
| #end | IMG | 仓库二维码 | ❌ |

**最小可发版本**：#0 + #1.3 + #3 三段动图 + 一张二维码就能发。
