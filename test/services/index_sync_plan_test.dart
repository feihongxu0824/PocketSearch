import 'package:flutter_test/flutter_test.dart';
import 'package:zvec_photo_search/services/index_service.dart';

/// Locks the cold-start sync algorithm: given (dbIds, liveIds) it must
/// always partition dbIds into "stale" (drop) and "alreadyIndexed"
/// (skip encode). A regression here re-introduces the bug where
/// deleted photos keep appearing in search results — verified painful
/// in the 53→220 dataset migration.
void main() {
  group('IndexService.computeSyncPlan', () {
    test('empty DB and empty gallery → both buckets empty', () {
      final plan = IndexService.computeSyncPlan(
        dbIds: const [],
        liveIds: const {},
      );
      expect(plan.staleIds, isEmpty);
      expect(plan.alreadyIndexed, isEmpty);
    });

    test('first run: empty DB, gallery has photos → nothing to drop, nothing to skip', () {
      final plan = IndexService.computeSyncPlan(
        dbIds: const [],
        liveIds: {'a', 'b', 'c'},
      );
      expect(plan.staleIds, isEmpty);
      expect(plan.alreadyIndexed, isEmpty);
    });

    test('user wiped gallery: full DB, empty gallery → ALL stale, nothing skipped', () {
      final plan = IndexService.computeSyncPlan(
        dbIds: const ['a', 'b', 'c'],
        liveIds: const {},
      );
      expect(plan.staleIds, equals(['a', 'b', 'c']));
      expect(plan.alreadyIndexed, isEmpty);
    });

    test('warm restart: DB == gallery → all skipped, nothing stale', () {
      final plan = IndexService.computeSyncPlan(
        dbIds: const ['a', 'b', 'c'],
        liveIds: {'a', 'b', 'c'},
      );
      expect(plan.staleIds, isEmpty);
      expect(plan.alreadyIndexed, equals({'a', 'b', 'c'}));
    });

    test('mixed: some deleted, some kept, some new', () {
      // DB had: a, b, c, d
      // Gallery now: b, d, e, f
      // Expected: drop a + c (deleted); skip b + d (already encoded);
      //           e + f are new and live but they're NOT in dbIds, so
      //           computeSyncPlan does not surface them — they are
      //           handled by the encode loop scanning liveIds itself.
      final plan = IndexService.computeSyncPlan(
        dbIds: const ['a', 'b', 'c', 'd'],
        liveIds: {'b', 'd', 'e', 'f'},
      );
      expect(plan.staleIds, equals(['a', 'c']));
      expect(plan.alreadyIndexed, equals({'b', 'd'}));
    });

    test('preserves dbIds order in staleIds (deterministic delete batches)', () {
      final plan = IndexService.computeSyncPlan(
        dbIds: const ['z', 'y', 'x', 'w'],
        liveIds: const {},
      );
      // Order matters for stable batch-delete telemetry / reproducibility.
      expect(plan.staleIds, equals(['z', 'y', 'x', 'w']));
    });

    test('result collections are immutable (defensive against caller mutation)', () {
      final plan = IndexService.computeSyncPlan(
        dbIds: const ['a', 'b'],
        liveIds: {'a'},
      );
      expect(() => plan.staleIds.add('x'), throwsUnsupportedError);
      expect(() => plan.alreadyIndexed.add('x'), throwsUnsupportedError);
    });

    test('large input: 10k IDs partitioned correctly', () {
      // Sanity: linear-time algorithm shouldn't choke on production-size
      // libraries and the partition arithmetic must remain exact.
      final dbIds =
          List<String>.generate(10000, (i) => 'photo_$i'); // 0..9999
      final liveIds =
          {for (var i = 5000; i < 15000; i++) 'photo_$i'}; // 5000..14999
      final plan = IndexService.computeSyncPlan(
        dbIds: dbIds,
        liveIds: liveIds,
      );
      // Stale = 0..4999 (5000 photos in DB but no longer in gallery)
      expect(plan.staleIds.length, 5000);
      expect(plan.staleIds.first, 'photo_0');
      expect(plan.staleIds.last, 'photo_4999');
      // Already indexed = 5000..9999 (overlap of DB and gallery)
      expect(plan.alreadyIndexed.length, 5000);
      expect(plan.alreadyIndexed.contains('photo_5000'), isTrue);
      expect(plan.alreadyIndexed.contains('photo_9999'), isTrue);
      expect(plan.alreadyIndexed.contains('photo_4999'), isFalse);
    });
  });
}
