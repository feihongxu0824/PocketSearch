# 推文大纲：zvec 走向移动端 + 端侧语义搜图 + LLM 自然语言扩展

> 目标：一篇技术推文 / 长图文，一次讲清三件事 —— zvec 的移动端化、demo
> 实测、用 LLM 把"自然语言"接进端侧搜索。
>
> 风格：技术叙事，给开发者看，少营销词；图片/动图占位用 `[IMG]` /
> `[GIF]`，等真机回归后再补素材。

## Hook（30 秒钩子）

> 一句话：在你手机上，0.3 秒从 1 万张照片里捞出"海边日落 + 白色的猫"，
> 全程不联网。

`[GIF #0]` —— 主界面三连搜（手机视角）：输入 `sunset over the ocean` →
`white cat on a windowsill` → `latte art on a cup of coffee`，每条都在
半秒内出图。

---

## 第一部分：zvec 真正走向移动端

### 1.1 之前 zvec 在哪儿

- 一句话回顾：[`alibaba/zvec`](https://github.com/alibaba/zvec) 是阿里
  开源的轻量、in-process 向量数据库，过去主要在服务端 / 桌面端跑。
- 移动端的"在端侧跑向量库"长期是个空缺 —— SQLite + 手撸 cosine 不行
  （慢且不索引），HNSWLib 等库没有成熟的 Flutter 绑定。

### 1.2 现在：Flutter SDK + 端侧 FFI

- `zvec 0.4.0` 发布 [`zvec-ai/zvec-dart`](https://github.com/zvec-ai/zvec-dart)
  Flutter 包，Android (arm64-v8a) + iOS (arm64) 双平台预编译，
  `flutter pub get` 即用，**不需要手动编译 native**。
- 这意味着任何 Flutter app 都能在端侧塞一个真正的向量库进去，cosine /
  L2 / IP 度量俱全。

`[IMG #1]` —— 一张架构图：
- 左：手机相册 → MNN 跑 MobileCLIP-S1 image encoder → 512-d 向量
- 右：用户输入 → MNN 跑 text encoder → zvec 查询 → 结果
- 关键标注：**所有箭头都不出手机**

### 1.3 这个 demo 解决了什么

- 验证 zvec Flutter 包在真实场景下扛得住（1 万张图、冷启动增量同步、
  HEIC 格式、PhotoKit ID 含 `/` 等坑）。
- 给社区一个能直接 fork 的"端侧语义搜图"模版，参 [`zvec-android-demo`](https://github.com/...)。

---

## 第二部分：Demo —— 端侧语义搜图，效果实测

### 2.1 数据集

- 演示库：1 万张 [Unsplash Lite](https://unsplash.com/data)
  专业摄影 + 部分自拍 / 旅行图，覆盖 8 类场景。
- 不用聊天截图、外卖券，避免"垃圾池里搜什么都精准"的假象。
- 复现脚本：`scripts/download_demo_dataset.py`（30 分钟下载 + adb push）。

### 2.2 索引

- 冷启动后台增量同步：新照片自动 diff 入库，已删除的自动清理；进度实时
  显示在状态栏。
- 单张索引耗时（iPhone，待真机回归后补准确数字）：MNN image encoder
  ~__ ms / 张 + zvec insert ~__ ms。

`[GIF #2.2]` —— 冷启动增量同步动图：进度条从 0 跑到 100%，过程中可以
正常搜索。

### 2.3 搜索

- 现场录三连搜（英文 query），每条标注：
  - 输入 query
  - 等待时长（< 50 ms 端侧）
  - 命中数 / 候选数
- 推荐 query（来自 [`assets/demo_queries.json`](../assets/demo_queries.json)）：
  - `sunset over the ocean`
  - `neon lights of a downtown skyline`
  - `latte art on a cup of coffee`
  - `white cat sitting on a windowsill`
  - `snowy mountain peak`

`[GIF #2.3]` —— 三连搜核心动图（这个是推文最重要的素材）。

### 2.4 体验细节

- 点击结果 → 全屏预览 + 双指缩放
- 右上角 → 系统原生分享面板（导出原图）
- 离线 / 隐私：飞行模式开着也能搜

`[GIF #2.4]` —— 全屏预览 + 分享动图。

### 2.5 一行总结

> 端侧 1 万张候选 + 全英文 query + 离线 + < 50 ms 出结果 = 这套是真能跑的。

---

## 第三部分：自然语言扩展 —— 集成 LLM Query Agent

### 3.1 第二部分有个尴尬：MobileCLIP-S1 的英文围墙

- 输入 `去年夏天海边玩的照片` → CLIP BPE 退化为 byte-fallback → 嵌入近
  随机 → 搜不到。
- 而且“去年夏天”这种**时间意图** CLIP 根本无法处理 —— 需要语义理解 +
  日期推理。
- 解法：**接 LLM Agent**，同时输出视觉描述 + 结构化过滤条件。

### 3.2 设计原则：可选、可降级、不破坏离线

- 设置页两个模式：**Off**（纯离线 CLIP） / **Remote**（LLM Agent）。
- 默认开启 Remote 模式，使用 DashScope qwen-turbo。
- ON 时调用 OpenAI 兼容协议，**只发送 query 文本**（一般几个词），
  不发任何图片 / 嵌入 / EXIF。
- 网络任何错误（超时 / 401 / 解析失败）都自动降级回原始 query，搜索结果
  始终能出。
- **本地 LLM 已弃用**：实测发现 1.5B 模型在手机上推理需 60s+，
  UX 不可接受。

### 3.3 架构

```
              ┌───────────────────────────────────┐
              │ SettingsService (shared_preferences) │
              │   llmEnabled, baseUrl, apiKey, model │
              └─────────────┬─────────────────────┘
                            │ buildRewriter()
                            ▼
   ┌─────────────────────────────────────────────────┐
   │ QueryRewriter (interface)                        │
   ├──────────────────────────┬──────────────────────┤
   │ IdentityQueryRewriter    │ OpenAICompatibleQR   │
   │ (default, no-op)         │ (POST /chat/completions)│
   └──────────────────────────┴──────────────────────┘
                            │
                            ▼
   user query ──▶ rewriter ──▶ tokenize ──▶ MNN text encoder ──▶ zvec
```

关键代码：[`lib/services/query_rewriter.dart`](../lib/services/query_rewriter.dart)
+ [`lib/services/settings_service.dart`](../lib/services/settings_service.dart)。

### 3.4 Agent Prompt（精简版）

> 你是 photo-search query agent。输入用户查询，输出 JSON：
> - "visual"：4–15 词英文视觉描述（必填）
> - "date_start" / "date_end"：ISO-8601 日期（可选，有时间意图时填）
> - "geo"：地理围栅 bounding box（可选）
>
> 当前日期注入 prompt，用于解析“去年”“上周”“前天”等相对时间。

完整 prompt 见 [`docs/llm-query-rewriter.md`](llm-query-rewriter.md)。

### 3.5 实测 Agent 输出示例

| 用户输入                       | Agent 输出                                                          |
|--------------------------------|-------------------------------------------------------------------|
| 去年夏天海边玩的照片           | `{"visual":"people playing on a sunny beach","date_start":"2025-06-01","date_end":"2025-09-01"}` |
| 上周的狗狗照片               | `{"visual":"dog in a park with green grass","date_start":"2026-05-04","date_end":"2026-05-11"}` |
| 在上海拍的夜景               | `{"visual":"city skyline and street lights at night","geo":{"lat_min":31.2,...}}` |
| 白猫                           | `{"visual":"white cat sitting on a windowsill"}` |
| sunset by the sea              | `{"visual":"sunset by the sea"}` *(passthrough)* |

`[GIF #3.5]` —— 设置页选择 Remote → 输入中文 → 看到 Agent 输出（视觉描述 +
日期过滤）→ 出图。

### 3.6 隐私 & 性能

- 隐私：只发 query 文本到用户自己配的端点（DashScope / DeepSeek / OpenAI /
  自托管 Ollama 都行）。
- 性能预算：LLM Agent ~1–2s（qwen-turbo）+ CLIP encode ~25 ms +
  zvec query < 5 ms = **总计 < 2.5s**。
- 推荐配置：
  - 国内用户：DashScope `qwen-turbo`（默认）
  - OpenAI 用户：`gpt-4o-mini`
  - 自托管：Ollama `qwen2.5:3b` 或 `llama3.2:3b`

`[IMG #3.6]` —— 设置页截图（base url / api key / model 三个字段
+ 隐私说明）。

---

## 收尾

### 我们交付了什么

- ✅ zvec 端侧 Flutter SDK 验证（双平台预编译可用）
- ✅ 1 万张候选 + < 50 ms 离线搜图
- ✅ 可选 LLM 改写：自然语言 / 中文 → 英文视觉描述
- ✅ 全开源：[zvec-android-demo](https://github.com/...) Apache 2.0

### 后续

- [ ] Chinese-CLIP 直接替换 image/text encoder（消除对 LLM 的依赖）
- [ ] 元数据扩展：EXIF 时间 / 地理位置 → 结构化过滤
- [ ] Android 真机回归（缺设备，征集 tester）

### CTA

- 🔗 仓库：`https://github.com/<user>/zvec-android-demo`
- ⭐ Star / 🐛 Issue / 🔄 Fork 都欢迎
- 🎬 想要中文支持？把这条转出去 + 评论 `+1`，下版本优先排

`[IMG #end]` —— 仓库二维码。

---

## 素材清单（等真机回归后录制）

| 编号   | 类型 | 内容                                                         | 必须真机 |
|--------|------|--------------------------------------------------------------|----------|
| #0     | GIF  | Hook 三连搜                                                  | ✅       |
| #1     | IMG  | 架构图（mermaid 渲染 PNG）                                   | ❌       |
| #2.2   | GIF  | 冷启动增量同步                                                | ✅       |
| #2.3   | GIF  | 第二部分主搜索（英文 query）                                  | ✅       |
| #2.4   | GIF  | 全屏预览 + 分享                                              | ✅       |
| #3.5   | GIF  | LLM 改写 demo（中文输入 → 英文改写 → 出图）                  | ✅       |
| #3.6   | IMG  | Settings 页面截图                                             | ✅（或模拟器） |
| #end   | IMG  | 仓库二维码                                                   | ❌       |

**最小可发版本**：把 #0 / #2.3 / #3.5 三段动图录好就能发，其余可以后置。
