import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:zvec_photo_search/models/search_filters.dart';

/// Strategy for rewriting a user-facing search query into something a
/// CLIP text encoder is more likely to match against.
///
/// Implementations MUST be safe to swap at runtime: the search pipeline
/// always wraps a [QueryRewriter] regardless of whether the user has
/// opted into LLM rewriting. The default [IdentityQueryRewriter] is a
/// no-op so the offline / privacy guarantees of the app are preserved
/// when the user has not configured an LLM endpoint.
abstract class QueryRewriter {
  /// Returns a rewritten query (or the input unchanged if no rewrite
  /// is appropriate). Implementations MUST NOT throw on transient
  /// network failure — they should fall back to the original query
  /// and surface the error via [RewriteResult.error].
  Future<RewriteResult> rewrite(String userQuery);
}

/// Outcome of one rewrite attempt. Always carries an [effectiveQuery]
/// that the caller can feed straight into the CLIP text encoder.
class RewriteResult {
  /// Original, untouched user input (for UI display).
  final String original;

  /// Query that should actually be sent to the CLIP text encoder.
  /// Equals [original] when no rewrite happened.
  final String effectiveQuery;

  /// True when the rewriter actually changed the query.
  final bool wasRewritten;

  /// Non-null when the rewriter tried but failed (network, parse, …).
  /// In that case [effectiveQuery] falls back to [original].
  final String? error;

  /// Optional structured metadata filters (date range, geo bounding-box)
  /// extracted by the LLM agent. `null` when mode is off, the LLM did
  /// not detect any filterable intent, or the rewriter is the legacy
  /// visual-only variant.
  final SearchFilters? filters;

  const RewriteResult({
    required this.original,
    required this.effectiveQuery,
    required this.wasRewritten,
    this.error,
    this.filters,
  });

  factory RewriteResult.identity(String q) => RewriteResult(
        original: q,
        effectiveQuery: q,
        wasRewritten: false,
      );

  factory RewriteResult.rewritten(
    String original,
    String rewritten, {
    SearchFilters? filters,
  }) =>
      RewriteResult(
        original: original,
        effectiveQuery: rewritten,
        wasRewritten: original.trim() != rewritten.trim(),
        filters: filters,
      );

  factory RewriteResult.failed(String original, String error) => RewriteResult(
        original: original,
        effectiveQuery: original,
        wasRewritten: false,
        error: error,
      );
}

/// No-op rewriter. Used when the user has not enabled LLM rewriting.
/// Guarantees zero outbound network traffic.
class IdentityQueryRewriter implements QueryRewriter {
  const IdentityQueryRewriter();

  @override
  Future<RewriteResult> rewrite(String userQuery) async =>
      RewriteResult.identity(userQuery);
}

/// System prompt used by *both* the remote OpenAI-compatible rewriter
/// and the on-device LLM rewriter. Kept as a top-level constant so the
/// two implementations stay behaviourally aligned (same instructions,
/// same examples, same expected output shape).
///
/// The prompt instructs the LLM to output a **JSON object** with:
/// - `"visual"`: 4-15 word English visual description (REQUIRED)
/// - `"date_start"` / `"date_end"`: ISO-8601 date strings (optional)
/// - `"geo"`: bounding-box `{lat_min, lat_max, lng_min, lng_max}` (optional)
///
/// A date-context header (`Today is YYYY-MM-DD`) is prepended at call
/// time by [buildAgentPrompt] so the model can resolve relative dates.
const String kAgentPromptBody = '''
You are a photo-search query agent. Given a user query, output a JSON object.

Fields:
- "visual": 4-15 word English visual description of the photo content (REQUIRED).
  Focus on subjects, colors, setting, lighting. Drop emotional/possessive words.
- "date_start": inclusive start date, ISO-8601 (YYYY-MM-DD). Omit if no time intent.
- "date_end": exclusive end date, ISO-8601 (YYYY-MM-DD). Omit if no time intent.
- "geo": {"lat_min","lat_max","lng_min","lng_max"} bounding box. Omit if unsure.

Rules:
- date_start/date_end: ONLY include when the user EXPLICITLY mentions a time expression
  (e.g. "today", "last week", "2025", "yesterday", "去年", "上个月").
  Possessive words like "my" or "我的" do NOT imply any date.
- geo: use a city-wide bounding box (cover the full urban area, not just city center).
- If the query mentions BOTH a place AND a time, you MUST include BOTH "geo" AND
  date_start/date_end. Never drop one when both are present.

Output ONLY the JSON. No markdown fences, no explanation, no quotes around the JSON.

Examples:
User: 去年夏天海边玩的照片
{"visual":"people playing on a sunny beach in summer","date_start":"2025-06-01","date_end":"2025-09-01"}

User: 在北京拍的建筑
{"visual":"buildings and architecture in Beijing","geo":{"lat_min":39.4,"lat_max":41.1,"lng_min":115.4,"lng_max":117.5}}

User: 白猫
{"visual":"white cat indoors"}

User: 前天晚上的晚霞
{"visual":"sunset sky with colorful clouds in the evening","date_start":"2026-05-11","date_end":"2026-05-12"}

User: today photos
{"visual":"photos taken today","date_start":"2026-05-13","date_end":"2026-05-14"}

User: my dog playing in the park
{"visual":"dog playing in a grassy park"}

User: sunset by the sea
{"visual":"sunset over the ocean with golden light"}

User: 上周在东京吃的拉面
{"visual":"ramen noodles in a Japanese restaurant","date_start":"2026-05-04","date_end":"2026-05-11","geo":{"lat_min":35.5,"lat_max":35.9,"lng_min":139.5,"lng_max":139.9}}

User: photos in Paris last summer
{"visual":"streets and landmarks in Paris","date_start":"2025-06-01","date_end":"2025-09-01","geo":{"lat_min":48.8,"lat_max":48.9,"lng_min":2.2,"lng_max":2.5}}
''';

/// Build the full agent system prompt by prepending the current date.
///
/// The [now] parameter allows deterministic testing.
String buildAgentPrompt({DateTime? now}) {
  final d = now ?? DateTime.now();
  final weekday = const [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ][d.weekday - 1];
  final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
  return 'Today is $dateStr ($weekday). Use this to resolve relative dates '
      '("last year", "yesterday", etc.).\n\n$kAgentPromptBody';
}

// ---------------------------------------------------------------------------
// Lite prompt for on-device LLMs with small KV-cache (e.g. 1280 tokens).
// Keeps the same JSON contract but drastically shorter (~400 chars total
// including date header) to fit within budget.
// ---------------------------------------------------------------------------

/// Compact agent prompt body for on-device models. Same JSON output contract
/// as [kAgentPromptBody] but with minimal instructions and 1 example.
const String kAgentPromptBodyLite = '''
Output a JSON object with:
- "visual": 4-15 word English description of photo content (REQUIRED)
- "date_start": YYYY-MM-DD start (optional)
- "date_end": YYYY-MM-DD end (optional)
- "geo": {"lat_min","lat_max","lng_min","lng_max"} (optional)
Output ONLY JSON, no explanation.

Example:
User: photos from last summer at the beach
{"visual":"people playing on a sunny beach","date_start":"2025-06-01","date_end":"2025-09-01"}
''';

/// Lite version of [buildAgentPrompt] for on-device models with limited
/// context windows. Same date injection, much shorter body.
String buildAgentPromptLite({DateTime? now}) {
  final d = now ?? DateTime.now();
  final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
  return 'Today is $dateStr.\n$kAgentPromptBodyLite';
}

/// Legacy visual-only prompt kept for reference / fallback.
const String kVisualRewritePrompt = '''
You rewrite user search queries into short English visual descriptions
that a CLIP-style image encoder can match against photos.

Rules:
- Output ONLY the rewritten English description, no preamble, no quotes.
- Keep it to 4-15 words.
- Focus on visual content: subjects, colors, setting, lighting, weather.
- Drop temporal/location words that aren't visually depicted.
- Drop emotional or possessive words ("my", "love", "missing") that
  aren't visual.
- If the input is already a short English visual description, return
  it unchanged.

Examples:
User: 去年夏天海边玩的照片
Rewrite: people playing on a sunny beach in summer

User: 我家那只白猫
Rewrite: white cat indoors

User: 深夜下班回家路上
Rewrite: city street at night with neon lights

User: sunset by the sea
Rewrite: sunset by the sea
''';

/// Strip surrounding quotes (straight, single, smart Chinese / English)
/// that some LLMs add despite the prompt forbidding it.
String stripWrappingQuotes(String s) {
  var out = s;
  final pairs = ['"', "'", '\u201c\u201d', '\u2018\u2019', '\u300c\u300d', '\u300e\u300f'];
  for (final p in pairs) {
    if (p.length == 1) {
      if (out.startsWith(p) && out.endsWith(p) && out.length >= 2) {
        out = out.substring(1, out.length - 1);
      }
    } else {
      if (out.startsWith(p[0]) && out.endsWith(p[1]) && out.length >= 2) {
        out = out.substring(1, out.length - 1);
      }
    }
  }
  return out.trim();
}

// ---------------------------------------------------------------------------
// Agent output parser — shared by both remote and local rewriters
// ---------------------------------------------------------------------------

/// Regex that extracts the first `{...}` JSON object from the LLM output,
/// even when the model wraps it in markdown fences or adds preamble text.
final RegExp _jsonObjectRe = RegExp(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}');

/// Parse raw LLM output into a [RewriteResult] with optional [SearchFilters].
///
/// Fallback chain:
/// 1. Try `jsonDecode` on the full output.
/// 2. If that fails, extract the first `{...}` substring and try again.
/// 3. If both fail, treat the whole output as a plain visual description
///    (backward-compatible with the old rewrite-only prompt).
RewriteResult parseAgentOutput(String raw, String original) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return RewriteResult.failed(original, 'empty response');
  }

  Map<String, dynamic>? json;

  // 1. Try full parse.
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) json = decoded;
  } catch (_) {}

  // 2. Extract first JSON object.
  if (json == null) {
    final m = _jsonObjectRe.firstMatch(trimmed);
    if (m != null) {
      try {
        final decoded = jsonDecode(m.group(0)!);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
    }
  }

  // 3. Fallback: treat whole output as visual description.
  if (json == null) {
    final cleaned = stripWrappingQuotes(trimmed);
    if (cleaned.isEmpty) {
      return RewriteResult.failed(original, 'empty response');
    }
    return RewriteResult.rewritten(original, cleaned);
  }

  // Extract visual description.
  final visual = (json['visual'] as String?)?.trim();
  if (visual == null || visual.isEmpty) {
    // Model gave JSON but without the required "visual" key.
    return RewriteResult.failed(original, 'missing "visual" in JSON output');
  }

  // Extract optional filters.
  final filters = SearchFilters.fromLlmJson(json);

  return RewriteResult.rewritten(
    original,
    stripWrappingQuotes(visual),
    filters: filters.hasAny ? filters : null,
  );
}

/// OpenAI-compatible chat-completions client. Works with OpenAI itself
/// and any vendor that mirrors the `/v1/chat/completions` schema
/// (DeepSeek, Qwen via DashScope-compatible endpoint, Together, etc.).
///
/// The prompt is intentionally short and deterministic so even a small
/// model (e.g. `gpt-4o-mini`, `deepseek-chat`, `qwen-turbo`) can answer
/// in <500ms.
class OpenAICompatibleQueryRewriter implements QueryRewriter {
  final String baseUrl;
  final String apiKey;
  final String model;
  final Duration timeout;
  final http.Client _client;

  /// Visible-for-testing: lets unit tests inject a mock client.
  OpenAICompatibleQueryRewriter({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeout = const Duration(seconds: 8),
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<RewriteResult> rewrite(String userQuery) async {
    final trimmed = userQuery.trim();
    if (trimmed.isEmpty) return RewriteResult.identity(userQuery);

    final uri = Uri.parse('${_normalizedBase()}/chat/completions');
    final body = jsonEncode({
      'model': model,
      'temperature': 0.0,
      'max_tokens': 120,
      'messages': [
        {'role': 'system', 'content': buildAgentPrompt()},
        {'role': 'user', 'content': trimmed},
      ],
    });

    try {
      final resp = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: body,
          )
          .timeout(timeout);

      if (resp.statusCode != 200) {
        return RewriteResult.failed(
          userQuery,
          'HTTP ${resp.statusCode}: ${_truncate(resp.body, 200)}',
        );
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final choices = data['choices'] as List?;
      final content = choices?.isNotEmpty == true
          ? (choices!.first['message']?['content'] as String?)
          : null;

      if (content == null || content.trim().isEmpty) {
        return RewriteResult.failed(userQuery, 'empty response');
      }

      return parseAgentOutput(content, userQuery);
    } on TimeoutException {
      return RewriteResult.failed(userQuery, 'timeout');
    } catch (e) {
      return RewriteResult.failed(userQuery, '$e');
    }
  }

  String _normalizedBase() {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  static String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';

  void dispose() => _client.close();
}
