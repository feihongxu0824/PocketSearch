import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:pocketsearch/models/personal_source_document.dart';

class TextSearchService {
  TextSearchService({PersonalSourcesClient? client})
    : _client = client ?? const PersonalSourcesClient();

  final PersonalSourcesClient _client;
  final List<PersonalSourceDocument> _documents = [];

  List<PersonalSourceDocument> get documents => List.unmodifiable(_documents);

  Future<void> syncSystemSources() async {
    if (!Platform.isIOS) return;
    final docs = await _client.fetchDocuments();
    _merge(docs);
  }

  Future<void> importFiles() async {
    if (!Platform.isIOS) return;
    final docs = await _client.importFiles();
    _merge(docs);
  }

  void replaceForTesting(List<PersonalSourceDocument> docs) {
    _documents
      ..clear()
      ..addAll(docs);
  }

  List<TextSearchResult> search(String query, {int topK = 20}) {
    final queryTerms = tokenize(query).toSet();
    if (queryTerms.isEmpty || _documents.isEmpty) return const [];

    final docFreq = <String, int>{};
    for (final doc in _documents) {
      for (final term in tokenize(doc.searchableText).toSet()) {
        docFreq[term] = (docFreq[term] ?? 0) + 1;
      }
    }

    final scored = <TextSearchResult>[];
    for (final doc in _documents) {
      final text = doc.searchableText;
      final terms = tokenize(text);
      if (terms.isEmpty) continue;

      final counts = <String, int>{};
      for (final term in terms) {
        counts[term] = (counts[term] ?? 0) + 1;
      }

      var score = 0.0;
      for (final term in queryTerms) {
        final tf = counts[term] ?? 0;
        if (tf == 0) continue;
        final idf = math.log(
          1 + (_documents.length + 1) / ((docFreq[term] ?? 0) + 1),
        );
        score += (1 + math.log(tf)) * idf;
      }
      if (score <= 0) continue;

      final snippet = buildSnippet(doc.title, doc.body, queryTerms);
      scored.add(
        TextSearchResult(
          document: doc,
          score: score,
          snippet: snippet,
          highlightRanges: findHighlightRanges(snippet, queryTerms),
          matchedFields: matchedFields(doc, queryTerms),
        ),
      );
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }

  void _merge(List<PersonalSourceDocument> incoming) {
    final byId = {
      for (final doc in _documents) doc.id: doc,
      for (final doc in incoming) doc.id: doc,
    };
    _documents
      ..clear()
      ..addAll(byId.values);
  }

  static List<String> tokenize(String input) {
    return RegExp(r"[\p{L}\p{N}']+", unicode: true)
        .allMatches(input.toLowerCase())
        .map((m) => m.group(0)!)
        .where((s) => s.length > 1)
        .toList();
  }

  static String buildSnippet(String title, String body, Set<String> terms) {
    final haystack = body.trim().isEmpty ? title : body.trim();
    if (haystack.isEmpty) return title;
    final lower = haystack.toLowerCase();
    final first = terms
        .map(lower.indexOf)
        .where((i) => i >= 0)
        .fold<int?>(null, (best, i) => best == null ? i : math.min(best, i));
    if (first == null) {
      return haystack.length <= 180
          ? haystack
          : '${haystack.substring(0, 177)}...';
    }
    final start = math.max(0, first - 60);
    final end = math.min(haystack.length, first + 120);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < haystack.length ? '...' : '';
    return '$prefix${haystack.substring(start, end)}$suffix';
  }

  static List<TextRange> findHighlightRanges(String text, Set<String> terms) {
    final ranges = <TextRange>[];
    final lower = text.toLowerCase();
    for (final term in terms) {
      var start = 0;
      while (true) {
        final i = lower.indexOf(term, start);
        if (i < 0) break;
        ranges.add(TextRange(start: i, end: i + term.length));
        start = i + term.length;
      }
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  static List<String> matchedFields(
    PersonalSourceDocument doc,
    Set<String> terms,
  ) {
    final fields = <String>[];
    bool contains(String value) {
      final lower = value.toLowerCase();
      return terms.any(lower.contains);
    }

    if (contains(doc.title)) fields.add('title');
    if (contains(doc.body)) fields.add('body');
    if (contains(doc.sourceName)) fields.add('source');
    return fields;
  }
}

class PersonalSourcesClient {
  const PersonalSourcesClient();

  static const _channel = MethodChannel('app.pocketsearch/personal_sources');

  Future<List<PersonalSourceDocument>> fetchDocuments() async {
    final raw = await _channel.invokeListMethod<dynamic>('fetchDocuments');
    return _parse(raw);
  }

  Future<List<PersonalSourceDocument>> importFiles() async {
    final raw = await _channel.invokeListMethod<dynamic>('importFiles');
    return _parse(raw);
  }

  List<PersonalSourceDocument> _parse(List<dynamic>? raw) {
    return (raw ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(PersonalSourceDocument.fromMap)
        .where((doc) => doc.id.isNotEmpty && doc.title.isNotEmpty)
        .toList();
  }
}
