import 'dart:math' as math;
import 'dart:typed_data';

/// Vector math helpers used by CLIP service and tests.
/// Kept free of Flutter / FFI dependencies so they can be unit-tested.
class VecMath {
  VecMath._();

  /// L2-normalize [vector] in place. Returns the same buffer for chaining.
  /// If the vector has zero norm it is left untouched.
  static Float32List l2NormalizeInPlace(Float32List vector) {
    double norm = 0;
    for (var i = 0; i < vector.length; i++) {
      norm += vector[i] * vector[i];
    }
    if (norm <= 0) return vector;
    final invNorm = 1.0 / math.sqrt(norm);
    for (var i = 0; i < vector.length; i++) {
      vector[i] *= invNorm;
    }
    return vector;
  }

  /// Returns a new L2-normalized copy of [vector].
  static Float32List l2Normalize(Float32List vector) {
    final out = Float32List.fromList(vector);
    return l2NormalizeInPlace(out);
  }

  /// Cosine similarity between two equal-length vectors.
  /// Returns 0 if either vector has zero norm.
  static double cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) {
      throw ArgumentError('Vector length mismatch: ${a.length} vs ${b.length}');
    }
    double dot = 0, na = 0, nb = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na <= 0 || nb <= 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }
}
