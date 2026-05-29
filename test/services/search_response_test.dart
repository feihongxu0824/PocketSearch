import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsearch/services/search_service.dart';
import 'package:pocketsearch/services/vector_store.dart';

void main() {
  group('SearchResponse', () {
    test('carries results, timing, and total count', () {
      final results = [
        PhotoSearchResult(photoId: 'a', photoPath: '/p/a.jpg', score: 0.9),
        PhotoSearchResult(photoId: 'b', photoPath: '/p/b.jpg', score: 0.8),
      ];
      final resp = SearchResponse(
        results: results,
        queryTimeMs: 42,
        totalPhotos: 1234,
      );

      expect(resp.results.length, 2);
      expect(resp.results.first.photoId, 'a');
      expect(resp.queryTimeMs, 42);
      expect(resp.totalPhotos, 1234);
    });

    test('empty results are allowed', () {
      final resp = SearchResponse(
        results: const [],
        queryTimeMs: 10,
        totalPhotos: 0,
      );
      expect(resp.results, isEmpty);
      expect(resp.totalPhotos, 0);
    });
  });

  group('PhotoSearchResult', () {
    test('stores fields verbatim', () {
      final r = PhotoSearchResult(
        photoId: 'id-1',
        photoPath: '/tmp/photo.jpg',
        score: 0.73,
      );
      expect(r.photoId, 'id-1');
      expect(r.photoPath, '/tmp/photo.jpg');
      expect(r.score, 0.73);
    });
  });
}
