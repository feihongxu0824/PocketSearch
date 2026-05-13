import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvec_photo_search/utils/vec_math.dart';

void main() {
  group('VecMath.l2NormalizeInPlace', () {
    test('produces unit-length vector for non-zero input', () {
      final v = Float32List.fromList([3.0, 4.0]);
      VecMath.l2NormalizeInPlace(v);

      expect(v[0], closeTo(0.6, 1e-6));
      expect(v[1], closeTo(0.8, 1e-6));

      double norm = 0;
      for (final x in v) {
        norm += x * x;
      }
      expect(math.sqrt(norm), closeTo(1.0, 1e-6));
    });

    test('leaves zero vector unchanged', () {
      final v = Float32List.fromList([0.0, 0.0, 0.0]);
      VecMath.l2NormalizeInPlace(v);
      expect(v.every((x) => x == 0.0), isTrue);
    });

    test('returns the same buffer (in-place)', () {
      final v = Float32List.fromList([1.0, 2.0, 3.0]);
      final out = VecMath.l2NormalizeInPlace(v);
      expect(identical(out, v), isTrue);
    });

    test('works on 512-dim random vector', () {
      final rng = math.Random(42);
      final v = Float32List(512);
      for (var i = 0; i < v.length; i++) {
        v[i] = rng.nextDouble() * 2 - 1;
      }
      VecMath.l2NormalizeInPlace(v);
      double norm = 0;
      for (final x in v) {
        norm += x * x;
      }
      expect(math.sqrt(norm), closeTo(1.0, 1e-5));
    });
  });

  group('VecMath.l2Normalize', () {
    test('returns a new buffer, leaving original untouched', () {
      final v = Float32List.fromList([3.0, 4.0]);
      final out = VecMath.l2Normalize(v);
      expect(identical(out, v), isFalse);
      expect(v[0], 3.0);
      expect(v[1], 4.0);
      expect(out[0], closeTo(0.6, 1e-6));
      expect(out[1], closeTo(0.8, 1e-6));
    });
  });

  group('VecMath.cosineSimilarity', () {
    test('returns 1.0 for identical unit vectors', () {
      final a = VecMath.l2Normalize(Float32List.fromList([1.0, 2.0, 3.0]));
      expect(VecMath.cosineSimilarity(a, a), closeTo(1.0, 1e-6));
    });

    test('returns -1.0 for opposite vectors', () {
      final a = Float32List.fromList([1.0, 0.0]);
      final b = Float32List.fromList([-1.0, 0.0]);
      expect(VecMath.cosineSimilarity(a, b), closeTo(-1.0, 1e-6));
    });

    test('returns 0 for orthogonal vectors', () {
      final a = Float32List.fromList([1.0, 0.0]);
      final b = Float32List.fromList([0.0, 1.0]);
      expect(VecMath.cosineSimilarity(a, b), closeTo(0.0, 1e-6));
    });

    test('returns 0 when either vector is zero', () {
      final a = Float32List.fromList([0.0, 0.0]);
      final b = Float32List.fromList([1.0, 1.0]);
      expect(VecMath.cosineSimilarity(a, b), 0.0);
      expect(VecMath.cosineSimilarity(b, a), 0.0);
    });

    test('throws ArgumentError on length mismatch', () {
      final a = Float32List.fromList([1.0, 0.0]);
      final b = Float32List.fromList([1.0, 0.0, 0.0]);
      expect(
        () => VecMath.cosineSimilarity(a, b),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
