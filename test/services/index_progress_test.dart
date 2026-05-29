import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsearch/services/index_service.dart';

void main() {
  group('IndexProgress', () {
    test('progress is current/total', () {
      final p = IndexProgress(current: 25, total: 100);
      expect(p.progress, closeTo(0.25, 1e-9));
    });

    test('progress is 0 when total is 0', () {
      final p = IndexProgress(current: 0, total: 0);
      expect(p.progress, 0);
    });

    test('isComplete when current+failed >= total', () {
      expect(IndexProgress(current: 100, total: 100).isComplete, isTrue);
      expect(IndexProgress(current: 101, total: 100).isComplete, isTrue);
      expect(IndexProgress(current: 99, total: 100).isComplete, isFalse);
      // Failures count toward completion: a single HEIC decode error
      // must not pin the status bar in "indexing" forever.
      expect(
        IndexProgress(current: 99, total: 100, failedCount: 1).isComplete,
        isTrue,
      );
    });

    test('carries optional current photo path', () {
      final p = IndexProgress(
        current: 1,
        total: 2,
        currentPhotoPath: '/tmp/a.jpg',
      );
      expect(p.currentPhotoPath, '/tmp/a.jpg');
    });
  });

  group('IndexStatus', () {
    test('enum has the expected states', () {
      expect(IndexStatus.values, containsAll(<IndexStatus>[
        IndexStatus.idle,
        IndexStatus.indexing,
        IndexStatus.complete,
        IndexStatus.error,
      ]));
    });
  });
}
