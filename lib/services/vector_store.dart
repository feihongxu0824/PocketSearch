import 'dart:io';
import 'dart:typed_data';

import 'package:zvec/zvec.dart';

/// Wrapper around zvec for vector storage and retrieval.
class VectorStore {
  Collection? _collection;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  int get count {
    if (_collection == null) return 0;
    final stats = _collection!.stats;
    final c = stats.docCount;
    stats.destroy();
    return c;
  }

  /// Initialize zvec and open/create the photo embeddings collection.
  ///
  /// If [dbPath] already exists (returning user), opens the existing
  /// collection. Otherwise creates a fresh one with the photo embedding
  /// schema. `Collection.createAndOpen` alone would crash on second launch
  /// because zvec requires the path to be absent.
  Future<void> initialize(String dbPath) async {
    if (_initialized) return;

    if (!Zvec.isInitialized) {
      Zvec.initialize();
    }

    if (Directory(dbPath).existsSync()) {
      _collection = Collection.open(dbPath);
    } else {
      final schema = CollectionSchema(name: 'photo_embeddings', fields: [
        VectorSchema('embedding', 512, indexParams: HnswIndexParams()),
        FieldSchema(name: 'photo_id', dataType: DataType.string),
        FieldSchema(name: 'photo_path', dataType: DataType.string),
        FieldSchema(name: 'indexed_at', dataType: DataType.int64),
      ]);
      try {
        _collection = Collection.createAndOpen(dbPath, schema);
      } finally {
        schema.destroy();
      }
    }
    _initialized = true;
  }

  /// Insert a photo embedding with metadata.
  void insert({
    required String photoId,
    required Float32List vector,
    required String photoPath,
  }) {
    assert(_initialized, 'VectorStore not initialized');

    final doc = Doc(id: photoId)
      ..setVector('embedding', vector)
      ..setField('photo_id', photoId)
      ..setField('photo_path', photoPath)
      ..setField('indexed_at', DateTime.now().millisecondsSinceEpoch);

    _collection!.insert([doc]);
    doc.destroy();
  }

  /// Build/optimize the HNSW index after batch inserts.
  void optimize() {
    assert(_initialized, 'VectorStore not initialized');
    _collection!.optimize();
  }

  /// Query for top-K most similar vectors.
  List<PhotoSearchResult> query(Float32List vector, {int topK = 20}) {
    assert(_initialized, 'VectorStore not initialized');

    final vq = VectorQuery(
      fieldName: 'embedding',
      vector: vector,
      topk: topK,
      outputFields: ['photo_id', 'photo_path'],
    );

    final results = _collection!.query(vq);
    final output = <PhotoSearchResult>[];

    for (final doc in results) {
      output.add(PhotoSearchResult(
        photoId: doc.getString('photo_id') ?? doc.pk ?? '',
        photoPath: doc.getString('photo_path') ?? '',
        score: doc.score,
      ));
    }

    vq.destroy();

    // zvec cosine metric: score = distance (lower = more similar).
    // Sort ascending so the best match (smallest distance) comes first.
    output.sort((a, b) => a.score.compareTo(b.score));
    return output;
  }

  /// Check if a photo has already been indexed.
  bool contains(String photoId) {
    if (!_initialized) return false;
    final fetched = _collection!.fetch([photoId]);
    return fetched.isNotEmpty;
  }

  /// Return all photo IDs currently stored in the collection.
  ///
  /// Implemented via a vector query over a dummy embedding with `topk`
  /// equal to the current document count — the score ordering is
  /// irrelevant because we only consume the primary keys.
  List<String> getAllPhotoIds() {
    if (!_initialized) return const [];
    final n = count;
    if (n == 0) return const [];

    final dummy = Float32List(512);
    dummy[0] = 1.0; // any non-zero vector works
    final vq = VectorQuery(
      fieldName: 'embedding',
      vector: dummy,
      topk: n,
      outputFields: const ['photo_id'],
    );
    try {
      final docs = _collection!.query(vq);
      final ids = <String>[];
      for (final doc in docs) {
        final pid = doc.getString('photo_id') ?? doc.pk;
        if (pid != null) ids.add(pid);
      }
      return ids;
    } finally {
      vq.destroy();
    }
  }

  /// Delete documents by primary key. No-op when [ids] is empty.
  void deleteByIds(List<String> ids) {
    if (!_initialized || ids.isEmpty) return;
    _collection!.delete(ids);
  }

  /// Close the underlying collection. Intentionally does NOT call
  /// `Zvec.shutdown()` because the native library is a process-wide
  /// singleton shared with future VectorStore instances (and with tests).
  /// The OS will reclaim all native resources on process exit.
  void dispose() {
    _collection?.close();
    _collection = null;
    _initialized = false;
  }
}

class PhotoSearchResult {
  final String photoId;
  final String photoPath;
  final double score;

  PhotoSearchResult({
    required this.photoId,
    required this.photoPath,
    required this.score,
  });
}
