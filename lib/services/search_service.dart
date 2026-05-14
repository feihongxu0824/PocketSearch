import 'package:zvec_photo_search/services/clip_service.dart';
import 'package:zvec_photo_search/services/tokenizer.dart';
import 'package:zvec_photo_search/services/vector_store.dart';

/// Handles text-to-image semantic search.
class SearchService {
  final ClipService _clip;
  final VectorStore _store;
  final Tokenizer _tokenizer;

  SearchService({
    required ClipService clip,
    required VectorStore store,
    required Tokenizer tokenizer,
  })  : _clip = clip,
        _store = store,
        _tokenizer = tokenizer;

  /// Perform semantic search: text query → matching photos.
  /// Returns results sorted by similarity score (highest first).
  /// [topK] caps the maximum number of results.
  /// [maxDistance] filters out results whose cosine distance exceeds this
  /// threshold (0.0–2.0). Defaults to 0.95 — roughly cosine-similarity
  /// >= 0.05, which suppresses total noise while keeping loose matches.
  SearchResponse search(String query, {int topK = 20, double maxDistance = 0.95}) {
    final stopwatch = Stopwatch()..start();

    // 1. Tokenize text
    final tokenIds = _tokenizer.encode(query);

    // 2. Encode text to embedding via CLIP text encoder
    final embedding = _clip.encodeText(tokenIds);

    // 3. Query zvec for nearest vectors (already sorted desc by score)
    final raw = _store.query(embedding, topK: topK);

    // 4. Filter by maximum distance threshold
    final results = raw.where((r) => r.score <= maxDistance).toList();

    stopwatch.stop();

    return SearchResponse(
      results: results,
      queryTimeMs: stopwatch.elapsedMilliseconds,
      totalPhotos: _store.count,
    );
  }
}

class SearchResponse {
  final List<PhotoSearchResult> results;
  final int queryTimeMs;
  final int totalPhotos;

  SearchResponse({
    required this.results,
    required this.queryTimeMs,
    required this.totalPhotos,
  });
}
