import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsearch/models/personal_source_document.dart';
import 'package:pocketsearch/services/text_search_service.dart';

void main() {
  group('TextSearchService', () {
    test('tokenizes unicode words and numbers', () {
      expect(
        TextSearchService.tokenize('Call Alice about Q3 预算, 10am.'),
        containsAll(['call', 'alice', 'about', 'q3', '预算', '10am']),
      );
    });

    test('returns ranked text results with snippets and highlights', () {
      final svc = TextSearchService();
      svc.replaceForTesting([
        PersonalSourceDocument(
          id: 'reminder:1',
          sourceType: PersonalSourceType.reminder,
          title: 'Buy coffee beans',
          body: 'Remember to buy Ethiopian coffee beans after lunch.',
          sourceName: 'Reminders',
          indexedAt: DateTime(2026),
        ),
        PersonalSourceDocument(
          id: 'calendar:1',
          sourceType: PersonalSourceType.calendar,
          title: 'Architecture review',
          body: 'Discuss retrieval ranking and source provenance.',
          sourceName: 'Calendar',
          indexedAt: DateTime(2026),
        ),
      ]);

      final results = svc.search('coffee beans');
      expect(results, hasLength(1));
      expect(results.first.document.id, 'reminder:1');
      expect(results.first.snippet, contains('coffee beans'));
      expect(results.first.highlightRanges, isNotEmpty);
      expect(results.first.matchedFields, contains('body'));
    });

    test('findHighlightRanges returns sorted ranges', () {
      final ranges = TextSearchService.findHighlightRanges('Alpha beta alpha', {
        'alpha',
        'beta',
      });
      expect(
        ranges,
        equals(const [
          TextRange(start: 0, end: 5),
          TextRange(start: 6, end: 10),
          TextRange(start: 11, end: 16),
        ]),
      );
    });
  });
}
