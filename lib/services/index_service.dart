import 'dart:async';

import 'package:photo_manager/photo_manager.dart';

import 'package:zvec_photo_search/services/clip_service.dart';
import 'package:zvec_photo_search/services/vector_store.dart';

/// Manages photo gallery scanning and incremental background indexing.
class IndexService {
  final ClipService _clip;
  final VectorStore _store;

  IndexStatus _status = IndexStatus.idle;
  IndexStatus get status => _status;

  int _indexedCount = 0;
  int get indexedCount => _indexedCount;

  int _totalCount = 0;
  int get totalCount => _totalCount;

  final _progressController = StreamController<IndexProgress>.broadcast();
  Stream<IndexProgress> get progressStream => _progressController.stream;

  /// Set of already indexed photo IDs to avoid re-processing.
  final Set<String> _indexedIds = {};

  IndexService({
    required ClipService clip,
    required VectorStore store,
  })  : _clip = clip,
        _store = store;

  /// Start incremental indexing of the photo gallery.
  /// Emits progress events via [progressStream].
  Future<void> startIndexing() async {
    if (_status == IndexStatus.indexing) return;
    _status = IndexStatus.indexing;

    // Request permission. We ONLY need image access; the default
    // `RequestType.common` also asks for video + audio, which fails on
    // Android 13+ because we do not declare those permissions in the
    // manifest, causing the whole request to return `denied`.
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: false,
        ),
      ),
    );
    if (!permission.isAuth && !permission.hasAccess) {
      _status = IndexStatus.error;
      // Emit an event so listeners (e.g. IndexStatusBar) rebuild and
      // can observe the new status.
      _progressController.add(IndexProgress(current: 0, total: 0));
      return;
    }

    // Get all image assets
    final albums = await PhotoManager.getAssetPathList(type: RequestType.image);
    if (albums.isEmpty) {
      _status = IndexStatus.complete;
      _progressController.add(IndexProgress(current: 0, total: 0));
      return;
    }

    final allAlbum = albums.first; // "Recent" / all photos

    // -----------------------------------------------------------------
    // Sync DB with the live photo gallery before encoding anything.
    //
    //  1. Page through MediaStore once and collect every live asset id.
    //  2. Drop DB records whose photo no longer exists (user deleted it).
    //  3. Mark already-indexed assets so the encode loop can skip them.
    //
    // This keeps cold start fast (only NEW photos get re-encoded) and
    // guarantees stale records from previous datasets cannot pollute
    // search results when the gallery contents change drastically.
    // -----------------------------------------------------------------
    final allAssets = <AssetEntity>[];
    final liveIds = <String>{};
    {
      const scanPageSize = 200;
      var p = 0;
      while (true) {
        final batch =
            await allAlbum.getAssetListPaged(page: p, size: scanPageSize);
        if (batch.isEmpty) break;
        allAssets.addAll(batch);
        for (final a in batch) {
          liveIds.add(a.id);
        }
        p++;
      }
    }

    final dbIds = _store.getAllPhotoIds();
    final plan = computeSyncPlan(dbIds: dbIds, liveIds: liveIds);
    if (plan.staleIds.isNotEmpty) {
      _store.deleteByIds(plan.staleIds);
    }
    // Pre-populate the in-memory dedup set with photos that are both
    // present on disk AND already encoded — avoids re-running CLIP on
    // them and lets us report accurate progress out of the gate.
    _indexedIds
      ..clear()
      ..addAll(plan.alreadyIndexed);

    _totalCount = allAssets.length;
    _indexedCount = _indexedIds.length;

    // Emit an early progress event so the status bar updates immediately
    // (before any encoding happens) when the gallery is fully cached.
    _progressController.add(IndexProgress(
      current: _indexedCount,
      total: _totalCount,
    ));

    const batchSize = 50;
    var processedSinceOptimize = 0;

    for (final asset in allAssets) {
      if (_indexedIds.contains(asset.id)) continue;

      try {
        final file = await asset.file;
        if (file == null) continue;

        final bytes = await file.readAsBytes();
        final embedding = _clip.encodeImage(bytes);

        _store.insert(
          photoId: asset.id,
          vector: embedding,
          photoPath: file.path,
        );

        _indexedIds.add(asset.id);
        _indexedCount++;
        processedSinceOptimize++;

        _progressController.add(IndexProgress(
          current: _indexedCount,
          total: _totalCount,
          currentPhotoPath: file.path,
        ));

        if (processedSinceOptimize >= batchSize * 5) {
          _store.optimize();
          processedSinceOptimize = 0;
        }
      } catch (e) {
        // Skip failed photos, continue indexing
        _indexedCount++;
        continue;
      }
    }

    // Final optimization
    _store.optimize();

    _status = IndexStatus.complete;
    _progressController.add(IndexProgress(
      current: _indexedCount,
      total: _totalCount,
      currentPhotoPath: null,
    ));
  }

  void dispose() {
    _progressController.close();
  }

  /// Pure helper: given the set of photo IDs already stored in the
  /// vector DB and the set of IDs currently visible in the gallery,
  /// decide which records are stale (must be deleted) and which are
  /// already indexed (must be skipped during encoding).
  ///
  /// Extracted as a static, side-effect-free function so its behavior
  /// can be locked down with unit tests — a regression here would
  /// silently re-introduce the "deleted photos still appear in search"
  /// bug and is easy to break with seemingly innocuous refactors.
  static IndexSyncPlan computeSyncPlan({
    required List<String> dbIds,
    required Set<String> liveIds,
  }) {
    final stale = <String>[];
    final alreadyIndexed = <String>{};
    for (final id in dbIds) {
      if (liveIds.contains(id)) {
        alreadyIndexed.add(id);
      } else {
        stale.add(id);
      }
    }
    return IndexSyncPlan(
      staleIds: List.unmodifiable(stale),
      alreadyIndexed: Set.unmodifiable(alreadyIndexed),
    );
  }
}

/// Result of [IndexService.computeSyncPlan].
class IndexSyncPlan {
  /// Photo IDs that are in the DB but no longer in the gallery; must be
  /// removed before searching to avoid stale results.
  final List<String> staleIds;

  /// Photo IDs present in BOTH the DB and the gallery; the encoder
  /// should skip them on cold start.
  final Set<String> alreadyIndexed;

  const IndexSyncPlan({
    required this.staleIds,
    required this.alreadyIndexed,
  });
}

enum IndexStatus { idle, indexing, complete, error }

class IndexProgress {
  final int current;
  final int total;
  final String? currentPhotoPath;

  IndexProgress({
    required this.current,
    required this.total,
    this.currentPhotoPath,
  });

  double get progress => total > 0 ? current / total : 0;
  bool get isComplete => current >= total;
}
