# 开发笔记：两个反直觉的工程坑

> 这份文档记录了 zvec-android-demo 在真机集成过程中踩到的两个反直觉问题，
> 以及它们的最小复现 case 和修复方式。
> 主推文（[blog-outline.md](blog-outline.md)）出于篇幅考虑没写这部分，
> 但代码里有相关注释和 integration test，留个详细出处方便后来者避雷。

---

## 坑 1：zvec 标量过滤的"字段缺失=放行"行为

### 现象

集成 Demo 早期版本，搜「澳门的吃饭照片」时 LLM Agent 输出的 filter 看上去完全正确：

```text
date_start = 2026-04-01
date_end   = 2026-05-01
geo bbox   = lat 22.1–22.5, lng 113.5–114.0
```

但搜索结果里赫然有几张是在我家拍的——根本没出过珠三角，怎么会被召回到澳门 bbox？

### 第一直觉（错的）

- ❌ filter 没生效？→ debug 日志显示 filter 表达式正确传给了 zvec
- ❌ EXIF 解析错了？→ 检查原始照片，没有 GPS 信息（家里室内拍的）
- ❌ HNSW 召回 top-K 之后又被某个回填逻辑打乱？→ 没有这种逻辑

### 真实根因

我对 zvec 的 filter 语义理解错了。原本以为它是 SQL 那一套：

> 字段缺失 → 比较结果 NULL/未知 → 该 doc 被排除

真机集成测试跑出来的结果是：

> **字段缺失 → 该 filter 谓词在该 doc 上不执行 → 等于 always-true → doc 被放行**

也就是说，"我家室内拍的照片没写 latitude / longitude 字段"被 zvec 当成了"这个 doc 不参与 lat/lng 过滤"，于是它被向量近邻挑上了——而不是被 bbox filter 排除。

### 复现（3 条数据的最小 case）

```dart
final col = createCollection(); // schema 包含 latitude / longitude

col.insert([
  Doc(id: 'A_macao')..setVector(...)..setField('latitude', 22.2)..setField('longitude', 113.5),
  Doc(id: 'B_home') ..setVector(...)..setField('latitude', 22.7)..setField('longitude', 114.5),
  Doc(id: 'C_no_gps')..setVector(...), // 故意不写 lat/lng
]);

final hits = col.query(VectorQuery(
  vector: ...,
  topk: 10,
  filter: 'latitude >= 22.1 AND latitude <= 22.5 AND '
          'longitude >= 113.5 AND longitude <= 114.0',
));

// 期望：只命中 A_macao
// 实际：A_macao + C_no_gps 都被召回
```

### 修复（一行代码）

索引阶段始终为 filterable 字段写入 sentinel 值：

```dart
// lib/services/vector_store.dart
doc.setField('latitude',   latitude   ?? 0.0);
doc.setField('longitude',  longitude  ?? 0.0);
doc.setField('created_at', createdAt  ?? 0);
```

`(0.0, 0.0)` 这个经纬度落在大西洋赤道上，几乎不可能命中任何真实 bbox，等价于把"无 GPS"显式标记成"位于赤道大西洋"——任何真实城市的 bbox filter 都会排除掉它。

### 同步要做的事

1. **schema 版本 bump**：`VectorStore.schemaVersion: 2 → 3`，触发已部署设备的自动重建索引（demo 里已经实现，依据是 `$dbPath.version` marker 文件）。
2. **integration test 钉死契约**：`integration_test/zvec_filter_test.dart` 里写一个 3 条数据的最小 case，断言"缺字段的 doc 不被 bbox filter 召回"。

### 教训

> **遇到向量库的"硬过滤"行为，永远不要相信记忆——
> 写一个 3 条数据的最小 case 真机跑一遍。**

不同向量库对"字段缺失"的处理路径不一样：

- 有的把它当 SQL NULL → 排除
- 有的把它当 always-true → 放行（zvec 是这一类）
- 有的需要显式 `IS NOT NULL` 判断

不写 sentinel 值就是把"我对引擎语义的假设"当成了"引擎的承诺"，这是迟早要出问题的。

---

## 坑 2：LLM Agent 的复合查询丢 filter

### 现象

QA 阶段批量测复合意图查询，发现明显规律：

```text
「澳门的上个月的照片」  ❌ Agent 输出只有 date，丢了 geo
「上海昨天的夜景」      ❌ Agent 输出只有 date，丢了 geo
「去年在东京吃的拉面」  ❌ Agent 输出只有 date，丢了 geo
```

5 个复合 case 里 4 个都丢 geo。

### 第一直觉（错的）

- ❌ prompt 写得不清楚？→ 重读了三遍，规则其实写得挺清楚
- ❌ 模型上下文不够？→ DashScope qwen-turbo 对这种短 prompt 完全够用
- ❌ JSON schema 不严格？→ 加了 schema 验证后还是丢

### 真实根因

不是模型"忘了写"，是模型**学到了一个我没教的偏见**。

最初版的 7 条 few-shot 示例是这样分布的：

| 示例 | date | geo |
|---|---|---|
| 1 | ✓ | ✗ |
| 2 | ✓ | ✗ |
| 3 | ✗ | ✓ |
| 4 | ✗ | ✓ |
| 5 | ✗ | ✗ |
| 6 | ✗ | ✗ |
| 7 | ✓ | ✗ |

**没有任何一条示例同时包含 date 和 geo**。

模型从这个分布里学到了一个隐式的统计偏见：「date 和 geo **二选一**」。所以拿到「澳门的上个月的照片」这种复合 query 时，它会"决策"——哪个意图更显著、就只输出哪个。

这是经典的 few-shot 任务分布泄露问题。

### 修复（强约束 Rule + 复合 few-shot）

在 `lib/services/query_rewriter.dart` 的 `kAgentPromptBody` 里加：

```text
Rule: If the query mentions BOTH a place AND a time, you MUST include
      BOTH "geo" AND date_start/date_end. Never drop one when both are present.
```

并补两条复合 few-shot（中文 + 英文各一，覆盖跨语言泛化）：

```text
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

### 验证

修复后跑 10 个 case：

- 5 个复合（中英各一半）：5/5 全过，date + geo 都正确输出
- 5 个单意图（仅 date / 仅 geo / 无 filter 各几个）：5/5 无回归

### 教训

> **few-shot 不只是给"格式样本"，它会泄露任务分布的统计偏见。
> 复合意图必须显式覆盖到 example 里。**

延伸推论：如果你的任务有 N 个独立维度，few-shot 至少要覆盖

1. 每个维度的"出现"和"不出现"两种情况
2. **多维度同时出现**的情况（这一条最容易漏）

否则模型从"维度永远不共存"的样本分布里偷偷学到独立性假设，复合查询就会暴雷。

---

## 这两个坑给我们的共同启示

| 坑 | 形式上的问题 | 本质问题 |
|---|---|---|
| 标量过滤缺字段=放行 | 引擎行为和我的假设不一致 | **没写最小 case 验证假设** |
| 复合查询丢 filter | LLM 输出不稳定 | **few-shot 分布缺一个维度组合** |

抽象出来都是同一类——**把"我以为"当成"实际是"**。

实操上的反向最佳实践：

1. **集成新引擎时，写 3 条数据的最小 case** 验证每条 filter 语义假设
2. **设计 few-shot 时，列一张矩阵** 把所有维度组合圈一遍，看哪些没被覆盖
3. **integration test 钉死你踩过的坑**——后人不会重新踩，未来重构也不会回滚契约

---

## 相关文件

- `lib/services/vector_store.dart` — sentinel 值写入逻辑（搜 `IMPORTANT`）
- `integration_test/zvec_filter_test.dart` — 缺字段不召回的契约测试
- `lib/services/query_rewriter.dart` — `kAgentPromptBody` 含完整 prompt（搜 `BOTH a place AND a time`）
- `docs/llm-query-rewriter.md` — Agent 整体设计 / 隐私 / 降级策略
