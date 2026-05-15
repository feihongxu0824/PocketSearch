# LLM Query Agent (optional)

> TL;DR. The default Zvec Photo Search experience is **fully offline**.
> This document covers the *opt-in* feature that improves recall on
> casually-phrased or non-English queries **and** supports metadata
> filtering (date range, geolocation). Two implementations ship:
> a fully **local** path (on-device LLM, zero network at inference
> time) and a **remote** OpenAI-compatible path that sends only the
> search text — never your photos — to the endpoint of your choosing.

## Why this exists

MobileCLIP-S1 was trained on English alt-text. Its text encoder works
beautifully on short visual descriptions (`sunset over the ocean`,
`white cat on a windowsill`) but degrades on:

- non-English queries — Chinese / Japanese / Korean tokens fall through
  to byte-fallback BPE, producing near-random embeddings.
- long sentences — `please show me the photos I took at the beach last
  summer` over-weights the function words.
- emotionally-loaded queries — `the day I felt the happiest` has no
  visual anchor.
- **temporal / spatial intent** — `去年夏天海边玩的照片` ("photos from
  the beach last summer") requires knowing the current date and
  reasoning about relative time, then filtering by photo creation date.

The query agent solves all of these by producing:
1. A **visual description** (4–15 English words) for CLIP matching.
2. Optional **date filters** (`date_start`, `date_end`) resolved from
   relative time expressions using the current date.
3. Optional **geo bounding-box** for location-aware filtering.

## What gets sent over the wire

**Only the search query**, typically a few words. Concretely the body
of the POST to `${baseUrl}/chat/completions` looks like:

```json
{
  "model": "gpt-4o-mini",
  "temperature": 0.0,
  "max_tokens": 120,
  "messages": [
    {"role": "system", "content": "Today is 2026-05-13 (Wednesday)...\n<agent-prompt>"},
    {"role": "user",   "content": "去年夏天海边玩的照片"}
  ]
}
```

The system prompt injects the current date so the model can resolve
relative time expressions. The expected output is **JSON**:

```json
{"visual": "people playing on a sunny beach in summer", "date_start": "2025-06-01", "date_end": "2025-09-01"}
```

**Never** sent:

- photo bytes
- thumbnails
- vector embeddings
- photo IDs / paths / EXIF
- any other state from your gallery

If you disable the toggle, the app makes zero outbound requests — the
HTTP client is never instantiated.

## Configuration

Settings → "LLM Query Agent (optional)" exposes two
modes via a radio group:

| Mode | Network at inference time | Best for |
|------|---------------------------|----------|
| **Off** | none | The original 100%-offline demo. |
| **Remote** *(default)* | one POST per search (query text only) | Natural language + date/geo filtering via any OpenAI-compatible API. |

> **Deprecated: Local mode.** On-device LLM mode (backed by
> `flutter_gemma`) was removed from the UI in May 2026 after
> real-device testing showed 1.5B-class models (Qwen 2.5, Gemma 3)
> require 60s+ per inference on mobile hardware (iPhone SE, Pixel 6a),
> making the UX unacceptable. The code (`LocalLlmManager`,
> `LocalLlmQueryRewriter`) remains in the repo for reference but
> `rewrite()` simply returns identity (pass-through).

All persistence goes through `shared_preferences`; nothing is uploaded.
The `buildRewriter()` factory in
[`SettingsService`](../lib/services/settings_service.dart) always
returns the no-op `IdentityQueryRewriter` when the active mode is not
ready (no API key configured, etc.) so misconfiguration silently
degrades to the offline default rather than failing the search.

### Remote mode (OpenAI-compatible API)

Settings fields:

| Field    | Default                                                | Notes                                                                 |
|----------|--------------------------------------------------------|-----------------------------------------------------------------------|
| Base URL | `https://dashscope.aliyuncs.com/compatible-mode/v1`    | Any OpenAI-compatible endpoint. See examples below.                   |
| API Key  | (must be configured)                                   | Stored in `shared_preferences`. Treat as a secret on shared devices.  |
| Model    | `qwen-turbo`                                           | Pick something small and fast — temperature is pinned to 0.          |

### Endpoint examples (all OpenAI-compatible)

| Provider       | Base URL                                                | Suggested model     |
|----------------|---------------------------------------------------------|---------------------|
| Aliyun DashScope (compat mode) | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-turbo` |
| OpenAI         | `https://api.openai.com/v1`                             | `gpt-4o-mini`       |
| DeepSeek       | `https://api.deepseek.com/v1`                           | `deepseek-chat`     |
| Together AI    | `https://api.together.xyz/v1`                           | `meta-llama/Llama-3.2-3B-Instruct-Turbo` |
| Self-hosted Ollama | `http://<host>:11434/v1`                            | any installed chat model |

## Prompt & Agent Design

The system prompt lives in
[`kAgentPromptBody` / `buildAgentPrompt()`](../lib/services/query_rewriter.dart).
Highlights:

- **Current date injection**: `buildAgentPrompt()` prepends
  `"Today is YYYY-MM-DD (Weekday)"` so the LLM can resolve
  "last year", "yesterday", "前天" etc.
- **Structured JSON output** with fields:
  - `"visual"` (required): 4–15 word English visual description
  - `"date_start"` / `"date_end"` (optional): ISO-8601 date strings
  - `"geo"` (optional): `{lat_min, lat_max, lng_min, lng_max}` bounding box
- Few-shot examples baked into the prompt; total prompt ≤300 tokens.
- Fallback-compatible: if the model outputs plain text instead of JSON,
  `parseAgentOutput()` gracefully degrades to visual-only mode.

### Output parsing (`parseAgentOutput`)

Three-layer fallback chain ensures robustness:
1. Try `jsonDecode` on the full output.
2. Extract first `{...}` via regex (handles markdown fences / preamble).
3. Treat whole output as plain visual description (legacy compatibility).

### Metadata filtering pipeline

```
User query → LLM → JSON → parseAgentOutput()
                              │
                    ┌─────────┼───────────┐
                    ▼                     ▼
             visual desc          SearchFilters
                    │                     │
                    ▼                     ▼
             CLIP encode        toZvecFilter() → scalar filter
                    │                     │
                    └───────┬─────────────┘
                            ▼
                 VectorStore.query(vector, filter: expr)
```

The `SearchFilters` class ([`lib/models/search_filters.dart`](../lib/models/search_filters.dart))
produces zvec scalar-filter expressions like:
`created_at >= 1717200000000 AND created_at < 1725148800000`

## Error handling

Every code path that touches the network falls back to the original
query and surfaces a small italic line under the search bar:

> *LLM rewrite failed (timeout); used the original query.*

The pipeline is designed so that **a broken endpoint never breaks
search** — the worst case is "behaves as if LLM toggle were off".

Common causes & symptoms:

| Error in UI                        | Likely cause                                    |
|------------------------------------|-------------------------------------------------|
| `HTTP 401: ...`                    | API key is wrong or expired                     |
| `HTTP 404: ...`                    | Base URL doesn't expose `/chat/completions`     |
| `timeout`                          | 8 s default; raise via `OpenAICompatibleQueryRewriter.timeout` |
| `empty response`                   | Model output was blank — usually a model misconfig |

## Latency budget

For a tweet-worthy "instant" feel, total search ≤ 500 ms. Rough split
on a Wi-Fi connection:

- LLM rewrite: 200–400 ms (depends on provider; `gpt-4o-mini` is ~250 ms)
- CLIP text encode: ~25 ms
- zvec query (10k photos): ~5 ms
- thumbnail render in grid: lazy, ~16 ms per visible cell

If the LLM round-trip is your bottleneck, prefer a co-located endpoint
(e.g. DeepSeek for users in mainland China) or self-hosted Ollama on a
LAN host.

## What this feature is *not*

- **Not** a full tool-calling agent. The model cannot call external
  APIs (calendars, maps). Instead, the current date is injected
  statically into the system prompt. This is sufficient for relative
  time reasoning without requiring tool-use capability.
- **Not** Chinese-CLIP. Switching the image encoder to a natively
  multilingual model is a different — and bigger — change. The LLM
  agent is the cheap, drop-in alternative that ships today.

## Vector Store Schema (v2)

The zvec collection includes metadata fields for scalar filtering:

| Field | Type | Source |
|-------|------|--------|
| `embedding` | vector(512) | MobileCLIP image encoder |
| `photo_id` | string | Sanitized asset ID (primary key) |
| `photo_path` | string | Raw asset ID for thumbnail loading |
| `indexed_at` | int64 | Epoch ms when indexed |
| `created_at` | int64 | Photo creation timestamp (epoch ms, from EXIF) |
| `latitude` | float64 | GPS latitude (from EXIF, 0 if unavailable) |
| `longitude` | float64 | GPS longitude (from EXIF, 0 if unavailable) |

Schema migration: on app launch, `VectorStore.initialize()` detects
old schema (missing `created_at`) and triggers a full re-index.

## Runtime architecture & co-existence

The app runs **three native runtimes** inside a single process:

| Runtime | Purpose | Binary size | Peak RSS | Source |
|---------|---------|-------------|----------|--------|
| **MNN** 2.9.x | CLIP image & text encoder (MobileCLIP-S1) | ~7 MB | ~150 MB | FFI via `mnn_flutter` |
| **LiteRT-LM** (MediaPipe GenAI) | On-device LLM (Gemma / Qwen / SmolLM) | ~12 MB | ~700 MB (1B int4) | `flutter_gemma` plugin |
| **zvec** (native C) | Cosine-similarity vector search | ~1 MB | depends on index size | FFI via `zvec_dart` |

### Why three instead of one?

- **LiteRT-LM is LLM-only**: it exposes `addQueryChunk → getResponse`
  (autoregressive generation with KV cache) and nothing else. CLIP’s
  Conv2D / ViT / dual-encoder topology cannot be expressed in its model
  format, and it has no `encodeImage(Tensor)` API.
- **MNN is a general ML runtime** but has no official Flutter binding
  for its LLM mode (MNN-LLM). Writing a full ffi layer for KV-cache-
  aware generation, session management, and foreground-service lifecycle
  would add ≥2 weeks of platform-specific glue.
- **zvec** is a tiny C library doing brute-force / IVF cosine search.
  Its job is entirely different from the two model runtimes.

So each component picks the runtime that fits its workload shape:

```
┌─────────────────────────────────────────────────────┐
│  User types: "去年夏天海边玩的照片"                    │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
          ┌───────────────────────────┐
          │  LLM Rewrite (LiteRT-LM)  │  ← query text only
          │  "beach sunset vacation"  │
          └─────────────┬─────────────┘
                         │
                         ▼
          ┌───────────────────────────┐
          │  CLIP Text Encode (MNN)   │  ← short English phrase → 512-d vec
          └─────────────┬─────────────┘
                         │
                         ▼
          ┌───────────────────────────┐
          │  Vector Search (zvec)     │  ← cosine kNN over gallery
          └─────────────┬─────────────┘
                         │
                         ▼
                   Top-K photo results
```

### Co-existence safety

Three runtimes sharing one process is safe on both Android and iOS under
the following conditions:

1. **GPU exclusivity**: both MNN and LiteRT-LM default to **CPU**. Do
   not enable Metal/Vulkan on both simultaneously — two runtimes
   allocating separate Metal command buffers from the same process can
   exhaust GPU-addressable memory on mid-tier phones.

2. **Peak memory budget**: CLIP (~150 MB) + Gemma 1B (~700 MB) + zvec
   index + Dart heap ≈ **1 GB resident**. This is fine on 8 GB+
   flagships. On 4–6 GB devices, steer users toward SmolLM 135M
   (~200 MB loaded) or keep mode=Off.

3. **Temporal separation**: CLIP *image* encode is bulk-run at
   background indexing time; LLM rewrite fires only at user-initiated
   search. They almost never overlap. CLIP *text* encode (~25 ms) runs
   sequentially *after* the LLM rewrite finishes, so there is no
   concurrent compute pressure.

4. **Thread pool isolation**: MNN spawns its own pthreads (default 4);
   MediaPipe uses platform-specific thread pools (GCD on iOS, fork-join
   on Android). They don’t share worker threads, so priority inversion
   or starvation is not a concern.

5. **Lifecycle independence**: `ClipService.dispose()`,
   `LocalLlmManager.uninstallAll()`, and `VectorStore.dispose()` each
   clean up their own native handles. No shared `close()` hook.

### Future simplification path

- If MNN-LLM ships an official Flutter binding, CLIP + LLM could
  consolidate onto a single MNN runtime, eliminating the LiteRT-LM
  dependency (~12 MB binary saving, simpler CI matrix).
- If LiteRT expands model-format support to include ViT / dual-encoder
  topologies, CLIP *could* migrate off MNN. Neither is imminent as of
  May 2025.
