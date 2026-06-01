import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsearch/services/tokenizer.dart';

/// Build a minimal CLIP-style vocab JSON string with:
/// - a small encoder mapping
/// - a couple of merge rules
///
/// The shape matches what [Tokenizer.loadFromJsonString] expects.
String _buildMiniVocab() {
  final encoder = <String, int>{
    // character-level entries used by BPE fallback
    'a': 100,
    'b': 101,
    'c': 102,
    'd': 103,
    'o': 104,
    'g': 105,
    't': 106,
    // merged pieces (after BPE merges are applied)
    'ca': 200,
    'cat</w>': 300,
    'dog</w>': 301,
    'a</w>': 302,
    // special tokens (must match constants inside Tokenizer)
    '<|startoftext|>': 49406,
    '<|endoftext|>': 49407,
  };

  final merges = <String>['c a', 'ca t</w>', 'd o', 'do g</w>'];

  return json.encode({'encoder': encoder, 'merges': merges});
}

void main() {
  group('Tokenizer', () {
    test('loadFromJsonString is idempotent and marks loaded', () {
      final tok = Tokenizer();
      expect(tok.isLoaded, isFalse);
      tok.loadFromJsonString(_buildMiniVocab());
      expect(tok.isLoaded, isTrue);
      // second call should be a no-op, not throw
      tok.loadFromJsonString(_buildMiniVocab());
      expect(tok.isLoaded, isTrue);
    });

    test('encode returns Int32List with contextLength=77', () {
      final tok = Tokenizer()..loadFromJsonString(_buildMiniVocab());
      final ids = tok.encode('cat');
      expect(ids.length, tok.contextLength);
      expect(tok.contextLength, 77);
    });

    test('encode wraps tokens with SOT and EOT', () {
      final tok = Tokenizer()..loadFromJsonString(_buildMiniVocab());
      final ids = tok.encode('cat');
      expect(ids[0], tok.sotToken);
      expect(ids[0], 49406);
      // find the EOT, must exist somewhere in the buffer
      final eotIndex = ids.indexOf(tok.eotToken);
      expect(eotIndex, greaterThan(0));
      // everything after EOT is padding (0)
      for (var i = eotIndex + 1; i < ids.length; i++) {
        expect(ids[i], 0);
      }
    });

    test('encode is case-insensitive / lowercases input', () {
      final tok = Tokenizer()..loadFromJsonString(_buildMiniVocab());
      final lower = tok.encode('cat');
      final upper = tok.encode('CAT');
      expect(lower, equals(upper));
    });

    test('empty string still yields SOT+EOT', () {
      final tok = Tokenizer()..loadFromJsonString(_buildMiniVocab());
      final ids = tok.encode('');
      expect(ids[0], tok.sotToken);
      expect(ids[1], tok.eotToken);
      // remaining positions are padding
      for (var i = 2; i < ids.length; i++) {
        expect(ids[i], 0);
      }
    });

    test('unknown tokens are silently skipped (no crash)', () {
      final tok = Tokenizer()..loadFromJsonString(_buildMiniVocab());
      // "xyz" characters are not in the mini vocab
      final ids = tok.encode('xyz');
      expect(ids[0], tok.sotToken);
      // EOT must still be emitted
      expect(ids.contains(tok.eotToken), isTrue);
    });

    test('encode is deterministic across calls', () {
      final tok = Tokenizer()..loadFromJsonString(_buildMiniVocab());
      final a = tok.encode('cat dog');
      final b = tok.encode('cat dog');
      expect(a, equals(b));
    });
  });
}
