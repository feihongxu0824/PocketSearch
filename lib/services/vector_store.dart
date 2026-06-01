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

  /// Schema version tag. Bump this when adding/removing fields so that
  /// [initialize] can detect stale collections and trigger a full re-index.
  static const int schemaVersion = 3;

  /// Initialize zvec and open/create the photo embeddings collection.
  ///
  /// If [dbPath] already exists (returning user), opens the existing
  /// collection. Otherwise creates a fresh one with the photo embedding
  /// schema. `Collection.createAndOpen` alone would crash on second launch
  /// because zvec requires the path to be absent.
  ///
  /// Returns `true` when a **migration** happened (old schema detected
  /// and deleted). The caller should trigger a full re-index in that case.
  Future<bool> initialize(String dbPath) async {
    if (_initialized) return false;

    if (!Zvec.isInitialized) {
      Zvec.initialize();
    }

    bool migrated = false;

    if (Directory(dbPath).existsSync()) {
      // Schema version marker file lives next to the DB directory.
      final versionFile = File('$dbPath.version');
      final currentVersion = versionFile.existsSync()
          ? int.tryParse(versionFile.readAsStringSync().trim()) ?? 0
          : 0;
      if (currentVersion < schemaVersion) {
        // Old schema detected — close any open handles and nuke the dir.
        try {
          final probe = Collection.open(dbPath);
          probe.close();
        } catch (_) {}
        if (Directory(dbPath).existsSync()) {
          Directory(dbPath).deleteSync(recursive: true);
        }
        migrated = true;
      } else {
        // Current schema — try to open; if a stale LOCK remains from a
        // killed process, remove it and retry once.
        try {
          _collection = Collection.open(dbPath);
        } catch (e) {
          if (e.toString().contains('lock')) {
            final lockFile = File('$dbPath/LOCK');
            if (lockFile.existsSync()) lockFile.deleteSync();
            _collection = Collection.open(dbPath);
          } else {
            rethrow;
          }
        }
      }
    }

    if (_collection == null) {
      final schema = CollectionSchema(
        name: 'photo_embeddings',
        fields: [
          VectorSchema('embedding', 512, indexParams: HnswIndexParams()),
          FieldSchema(name: 'photo_id', dataType: DataType.string),
          FieldSchema(name: 'photo_path', dataType: DataType.string),
          FieldSchema(name: 'indexed_at', dataType: DataType.int64),
          FieldSchema(name: 'created_at', dataType: DataType.int64),
          FieldSchema(name: 'latitude', dataType: DataType.float64),
          FieldSchema(name: 'longitude', dataType: DataType.float64),
        ],
      );
      try {
        _collection = Collection.createAndOpen(dbPath, schema);
      } finally {
        schema.destroy();
      }
      // Write schema version marker so future launches skip migration.
      File('$dbPath.version').writeAsStringSync('$schemaVersion');
    }
    _initialized = true;
    return migrated;
  }

  /// Insert a photo embedding with metadata.
  void insert({
    required String photoId,
    required Float32List vector,
    required String photoPath,
    int? createdAt,
    double? latitude,
    double? longitude,
  }) {
    assert(_initialized, 'VectorStore not initialized');

    final doc = Doc(id: photoId)
      ..setVector('embedding', vector)
      ..setField('photo_id', photoId)
      ..setField('photo_path', photoPath)
      ..setField('indexed_at', DateTime.now().millisecondsSinceEpoch);

    // IMPORTANT: zvec scalar filters treat MISSING fields as a pass-through
    // (the filter predicate does not run on docs that lack the field), so a
    // doc with no GPS would be wrongly recalled by `latitude >= X AND ...`.
    // We therefore always write a sentinel value (0) for filterable fields
    // and let the filter expression compare against real GPS coordinates.
    doc.setField('created_at', createdAt ?? 0);
    doc.setField('latitude', latitude ?? 0.0);
    doc.setField('longitude', longitude ?? 0.0);

    _collection!.insert([doc]);
    doc.destroy();
  }

  /// Build/optimize the HNSW index after batch inserts.
  void optimize() {
    assert(_initialized, 'VectorStore not initialized');
    _collection!.optimize();
  }

  /// Query for top-K most similar vectors.
  ///
  /// When [filter] is non-null it is passed as a zvec scalar-filter
  /// expression (e.g. `'created_at >= 1717200000000 AND created_at < 1725148800000'`).
  List<PhotoSearchResult> query(
    Float32List vector, {
    int topK = 20,
    String? filter,
  }) {
    assert(_initialized, 'VectorStore not initialized');

    final vq = VectorQuery(
      fieldName: 'embedding',
      vector: vector,
      topk: topK,
      outputFields: ['photo_id', 'photo_path'],
      filter: filter,
    );

    final results = _collection!.query(vq);
    final output = <PhotoSearchResult>[];

    for (final doc in results) {
      output.add(
        PhotoSearchResult(
          photoId: doc.getString('photo_id') ?? doc.pk ?? '',
          photoPath: doc.getString('photo_path') ?? '',
          score: doc.score,
        ),
      );
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
