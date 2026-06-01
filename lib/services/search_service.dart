import 'package:flutter/foundation.dart';

import 'package:pocketsearch/models/personal_source_document.dart';
import 'package:pocketsearch/services/clip_service.dart';
import 'package:pocketsearch/services/query_rewriter.dart';
import 'package:pocketsearch/services/tokenizer.dart';
import 'package:pocketsearch/services/vector_store.dart';

/// Handles text-to-image semantic search.
///
/// The pipeline is:
///   user query  ──▶  [QueryRewriter]  ──▶  tokenize  ──▶  CLIP text
///   encoder  ──▶  Zvec query  ──▶  filter by distance.
///
/// The default rewriter is [IdentityQueryRewriter] (no-op), so the
/// fully-offline guarantee is preserved unless the user explicitly
/// opts into LLM rewriting via Settings.
class SearchService {
  final ClipService _clip;
  final VectorStore _store;
  final Tokenizer _tokenizer;
  QueryRewriter _rewriter;

  SearchService({
    required ClipService clip,
    required VectorStore store,
    required Tokenizer tokenizer,
    QueryRewriter? rewriter,
  }) : _clip = clip,
       _store = store,
       _tokenizer = tokenizer,
       _rewriter = rewriter ?? const IdentityQueryRewriter();

  /// Hot-swap the rewriter (e.g. when the user toggles LLM in Settings).
  /// Existing in-flight searches are unaffected.
  void updateRewriter(QueryRewriter rewriter) {
    _rewriter = rewriter;
  }

  /// Perform semantic search: text query → matching photos.
  /// Returns results sorted by similarity score (highest first).
  /// [topK] caps the maximum number of results.
  /// [maxDistance] filters out results whose cosine distance exceeds this
  /// threshold (0.0–2.0). Defaults to 0.95 — roughly cosine-similarity
  /// >= 0.05, which suppresses total noise while keeping loose matches.
  Future<SearchResponse> search(
    String query, {
    int topK = 20,
    double maxDistance = 0.95,
  }) async {
    final totalSw = Stopwatch()..start();

    // 0. Optional LLM rewrite. Identity rewriter is synchronous-fast
    //    and does not perform any I/O, so the offline path stays cheap.
    final rewriteSw = Stopwatch()..start();
    final rewriteResult = await _rewriter.rewrite(query);
    rewriteSw.stop();

    final effective = rewriteResult.effectiveQuery;

    // 1. Tokenize text
    final tokenIds = _tokenizer.encode(effective);

    // 2. Encode text to embedding via CLIP text encoder
    final embedding = _clip.encodeText(tokenIds);

    // 3. Query Zvec for nearest vectors (already sorted desc by score)
    final filterExpr = rewriteResult.filters?.toZvecFilter();

    // Debug visibility: print rewrite + filter so it is easy to diagnose
    // "why was X recalled / not recalled" without rebuilding the app.
    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[search] q="$query"\n'
        '  effective="$effective"\n'
        '  filters=${rewriteResult.filters ?? 'none'}\n'
        '  zvec_filter=${filterExpr ?? 'none'}\n'
        '  rewrite_ms=${rewriteSw.elapsedMilliseconds}',
      );
    }

    final zvecSw = Stopwatch()..start();
    final raw = _store.query(embedding, topK: topK, filter: filterExpr);
    zvecSw.stop();

    // 4. Filter by maximum distance threshold
    final results = raw.where((r) => r.score <= maxDistance).toList();

    totalSw.stop();

    if (kDebugMode) {
      // ignore: avoid_print
      print(
        '[perf] query="$effective" total=${totalSw.elapsedMilliseconds}ms '
        'zvec=${zvecSw.elapsedMilliseconds}ms '
        'rewrite=${rewriteSw.elapsedMilliseconds}ms '
        'results=${results.length} photos=${_store.count}',
      );
    }

    return SearchResponse(
      results: results,
      queryTimeMs: totalSw.elapsedMilliseconds,
      rewriteTimeMs: rewriteSw.elapsedMilliseconds,
      totalPhotos: _store.count,
      rewrite: rewriteResult,
    );
  }
}

class SearchResponse {
  final List<PhotoSearchResult> results;
  final List<TextSearchResult> textResults;
  final int queryTimeMs;

  /// Time spent in the optional [QueryRewriter] (0 when the rewriter is
  /// the no-op [IdentityQueryRewriter]).
  final int rewriteTimeMs;
  final int totalPhotos;

  /// Snapshot of how the query was rewritten (or not). Defaults to an
  /// identity result so callers never see null and existing tests can
  /// keep constructing [SearchResponse] without supplying it.
  final RewriteResult rewrite;

  SearchResponse({
    required this.results,
    required this.queryTimeMs,
    required this.totalPhotos,
    this.textResults = const [],
    this.rewriteTimeMs = 0,
    RewriteResult? rewrite,
  }) : rewrite = rewrite ?? RewriteResult.identity('');

  bool get hasResults => results.isNotEmpty || textResults.isNotEmpty;
}
