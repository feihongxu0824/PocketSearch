import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// BPE Tokenizer for CLIP text encoder.
/// Implements the simple BPE tokenization used by OpenAI CLIP.
class Tokenizer {
  static const int _contextLength = 77;
  static const int _sotToken = 49406; // <|startoftext|>
  static const int _eotToken = 49407; // <|endoftext|>

  late Map<String, int> _encoder;
  late List<List<String>> _bpeMerges;
  late Map<String, String> _cache;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Load vocabulary and merge rules from bundled asset.
  Future<void> load(String vocabAssetPath) async {
    if (_loaded) return;
    final vocabJson = await rootBundle.loadString(vocabAssetPath);
    loadFromJsonString(vocabJson);
  }

  /// Load vocabulary from an already-decoded JSON string.
  /// Exposed for unit tests that don't have access to the asset bundle.
  void loadFromJsonString(String vocabJson) {
    if (_loaded) return;
    final vocabData = json.decode(vocabJson) as Map<String, dynamic>;

    _encoder = {};
    for (final entry
        in (vocabData['encoder'] as Map<String, dynamic>).entries) {
      _encoder[entry.key] = entry.value as int;
    }

    _bpeMerges = [];
    for (final merge in (vocabData['merges'] as List<dynamic>)) {
      final parts = (merge as String).split(' ');
      if (parts.length == 2) {
        _bpeMerges.add(parts);
      }
    }

    _cache = {};
    _loaded = true;
  }

  /// Context length that [encode] pads/truncates to.
  int get contextLength => _contextLength;

  /// Start-of-text token id.
  int get sotToken => _sotToken;

  /// End-of-text token id.
  int get eotToken => _eotToken;

  /// Tokenize text and return padded Int32List of length [_contextLength].
  Int32List encode(String text) {
    assert(_loaded, 'Tokenizer not loaded');

    text = text.toLowerCase().trim();
    final words = _tokenizeText(text);

    final tokens = <int>[_sotToken];
    for (final word in words) {
      final bpeTokens = _bpe(word);
      for (final token in bpeTokens) {
        final id = _encoder[token];
        if (id != null) {
          tokens.add(id);
        }
      }
    }
    tokens.add(_eotToken);

    // Pad or truncate to context length
    final result = Int32List(_contextLength);
    for (var i = 0; i < _contextLength; i++) {
      if (i < tokens.length) {
        result[i] = tokens[i];
      }
      // Remaining positions stay 0 (padding)
    }

    return result;
  }

  List<String> _tokenizeText(String text) {
    // Simple whitespace + punctuation tokenization
    // CLIP uses a regex-based pattern, simplified here
    final pattern = RegExp(
      r"'s|'t|'re|'ve|'m|'ll|'d|[\w]+|[^\s\w]+",
      caseSensitive: false,
    );
    final matches = pattern.allMatches(text);
    final words = <String>[];
    for (final match in matches) {
      // Add </w> suffix to mark word boundaries (CLIP convention)
      words.add('${match.group(0)!}</w>');
    }
    return words;
  }

  List<String> _bpe(String word) {
    if (_cache.containsKey(word)) {
      return _cache[word]!.split(' ');
    }

    var symbols = word.split('');
    if (symbols.isEmpty) return [];

    // Apply BPE merges
    for (final merge in _bpeMerges) {
      final first = merge[0];
      final second = merge[1];

      var i = 0;
      while (i < symbols.length - 1) {
        if (symbols[i] == first && symbols[i + 1] == second) {
          symbols = [
            ...symbols.sublist(0, i),
            '$first$second',
            ...symbols.sublist(i + 2),
          ];
        } else {
          i++;
        }
      }
    }

    _cache[word] = symbols.join(' ');
    return symbols;
  }
}
