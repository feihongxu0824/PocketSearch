import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:pocketsearch/models/search_filters.dart';
import 'package:pocketsearch/services/query_rewriter.dart';

void main() {
  group('IdentityQueryRewriter', () {
    test('returns the input unchanged and reports no rewrite', () async {
      const r = IdentityQueryRewriter();
      final out = await r.rewrite('sunset by the sea');
      expect(out.original, 'sunset by the sea');
      expect(out.effectiveQuery, 'sunset by the sea');
      expect(out.wasRewritten, isFalse);
      expect(out.error, isNull);
    });

    test('handles empty query without throwing', () async {
      const r = IdentityQueryRewriter();
      final out = await r.rewrite('');
      expect(out.effectiveQuery, '');
      expect(out.wasRewritten, isFalse);
    });
  });

  group('OpenAICompatibleQueryRewriter (mocked)', () {
    test('happy path: parses chat-completions response', () async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(
          req.url.toString(),
          'https://api.example.com/v1/chat/completions',
        );
        expect(req.headers['Authorization'], 'Bearer test-key');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['model'], 'fast-model');
        // The user message should carry the (trimmed) original query.
        final messages = body['messages'] as List;
        expect(messages.last['role'], 'user');
        expect(messages.last['content'], '我家那只白猫');
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'white cat indoors',
                },
              },
            ],
          }),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      });

      final r = OpenAICompatibleQueryRewriter(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'test-key',
        model: 'fast-model',
        client: mock,
      );

      final out = await r.rewrite('  我家那只白猫  ');
      expect(out.effectiveQuery, 'white cat indoors');
      expect(out.wasRewritten, isTrue);
      expect(out.error, isNull);

      r.dispose();
    });

    test('strips smart/straight quotes the model may add', () async {
      // Use Response.bytes with utf8-encoded body so the smart quotes
      // (U+201C / U+201D) round-trip cleanly through resp.bodyBytes.
      final mock = MockClient(
        (req) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '“sunset over the ocean”'},
                },
              ],
            }),
          ),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        ),
      );

      final r = OpenAICompatibleQueryRewriter(
        baseUrl: 'https://api.example.com/v1/',
        apiKey: 'k',
        model: 'm',
        client: mock,
      );

      final out = await r.rewrite('海边日落');
      expect(out.effectiveQuery, 'sunset over the ocean');
      expect(out.wasRewritten, isTrue);
    });

    test('non-200 response falls back to the original query', () async {
      final mock = MockClient(
        (req) async => http.Response('{"error":{"message":"bad key"}}', 401),
      );

      final r = OpenAICompatibleQueryRewriter(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'wrong',
        model: 'm',
        client: mock,
      );

      final out = await r.rewrite('cat');
      expect(out.effectiveQuery, 'cat');
      expect(out.wasRewritten, isFalse);
      expect(out.error, contains('HTTP 401'));
    });

    test('network exception falls back to the original query', () async {
      final mock = MockClient((req) async {
        throw const SocketException('offline');
      });

      final r = OpenAICompatibleQueryRewriter(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        model: 'm',
        client: mock,
      );

      final out = await r.rewrite('cat');
      expect(out.effectiveQuery, 'cat');
      expect(out.wasRewritten, isFalse);
      expect(out.error, isNotNull);
    });

    test('empty content from model is treated as failure (fallback)', () async {
      final mock = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '   '},
              },
            ],
          }),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        ),
      );

      final r = OpenAICompatibleQueryRewriter(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        model: 'm',
        client: mock,
      );

      final out = await r.rewrite('foo');
      expect(out.effectiveQuery, 'foo');
      expect(out.error, contains('empty'));
    });
  });
  group('OpenAI rewriter: JSON agent output with filters', () {
    test('parses JSON with date filters', () async {
      final mock = MockClient(
        (req) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '{"visual":"people on beach","date_start":"2025-06-01","date_end":"2025-09-01"}',
                  },
                },
              ],
            }),
          ),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        ),
      );

      final r = OpenAICompatibleQueryRewriter(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        model: 'm',
        client: mock,
      );

      final out = await r.rewrite('去年夏天海边');
      expect(out.effectiveQuery, 'people on beach');
      expect(out.wasRewritten, isTrue);
      expect(out.filters, isNotNull);
      expect(out.filters!.dateStartMs, isNotNull);
      expect(out.filters!.dateEndMs, isNotNull);
      expect(out.filters!.toZvecFilter(), contains('created_at'));
    });

    test('parses JSON with geo filters', () async {
      final mock = MockClient(
        (req) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '{"visual":"buildings in Beijing","geo":{"lat_min":39.4,"lat_max":41.1,"lng_min":115.4,"lng_max":117.5}}',
                  },
                },
              ],
            }),
          ),
          200,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        ),
      );

      final r = OpenAICompatibleQueryRewriter(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'k',
        model: 'm',
        client: mock,
      );

      final out = await r.rewrite('北京的建筑');
      expect(out.effectiveQuery, 'buildings in Beijing');
      expect(out.filters, isNotNull);
      expect(out.filters!.latMin, 39.4);
      expect(out.filters!.lngMax, 117.5);
    });
  });

  group('parseAgentOutput', () {
    test('full JSON parse', () {
      final result = parseAgentOutput(
        '{"visual":"sunset sky","date_start":"2025-06-01"}',
        'original',
      );
      expect(result.effectiveQuery, 'sunset sky');
      expect(result.filters?.dateStartMs, isNotNull);
    });

    test('extracts JSON from markdown fences', () {
      final result = parseAgentOutput(
        'Here is the result:\n```json\n{"visual":"white cat"}\n```',
        'original',
      );
      expect(result.effectiveQuery, 'white cat');
    });

    test('falls back to plain text', () {
      final result = parseAgentOutput('sunset over ocean', 'original');
      expect(result.effectiveQuery, 'sunset over ocean');
      expect(result.filters, isNull);
    });

    test('empty response returns failed', () {
      final result = parseAgentOutput('', 'original');
      expect(result.error, contains('empty'));
    });

    test('JSON without visual key returns failed', () {
      final result = parseAgentOutput(
        '{"date_start":"2025-06-01"}',
        'original',
      );
      expect(result.error, contains('visual'));
    });
  });

  group('buildAgentPrompt', () {
    test('includes current date', () {
      final prompt = buildAgentPrompt(now: DateTime(2026, 5, 13));
      expect(prompt, contains('2026-05-13'));
      expect(prompt, contains('Wednesday'));
    });
  });

  group('SearchFilters', () {
    test('toZvecFilter with date range', () {
      const f = SearchFilters(dateStartMs: 1000, dateEndMs: 2000);
      expect(f.toZvecFilter(), 'created_at >= 1000 AND created_at < 2000');
    });

    test('toZvecFilter with geo', () {
      const f = SearchFilters(
        latMin: 39.4,
        latMax: 41.1,
        lngMin: 115.4,
        lngMax: 117.5,
      );
      final filter = f.toZvecFilter()!;
      expect(filter, contains('latitude >= 39.4'));
      expect(filter, contains('longitude <= 117.5'));
    });

    test('toZvecFilter returns null when empty', () {
      const f = SearchFilters();
      expect(f.toZvecFilter(), isNull);
      expect(f.hasAny, isFalse);
    });

    test('fromLlmJson parses ISO dates', () {
      final f = SearchFilters.fromLlmJson({
        'date_start': '2025-06-01',
        'date_end': '2025-09-01',
      });
      expect(f.dateStartMs, DateTime(2025, 6, 1).millisecondsSinceEpoch);
      expect(f.dateEndMs, DateTime(2025, 9, 1).millisecondsSinceEpoch);
    });

    test('fromLlmJson parses geo', () {
      final f = SearchFilters.fromLlmJson({
        'geo': {
          'lat_min': 39.4,
          'lat_max': 41.1,
          'lng_min': 115.4,
          'lng_max': 117.5,
        },
      });
      expect(f.latMin, 39.4);
      expect(f.lngMax, 117.5);
    });

    test('toDisplayString formats date range', () {
      final f = SearchFilters(
        dateStartMs: DateTime(2025, 6, 1).millisecondsSinceEpoch,
        dateEndMs: DateTime(2025, 9, 1).millisecondsSinceEpoch,
      );
      expect(f.toDisplayString(), contains('2025-06-01'));
      expect(f.toDisplayString(), contains('2025-09-01'));
    });
  });
}

/// Minimal stand-in for `dart:io` SocketException so the test file does
/// not need a `dart:io` import (keeps it portable for Flutter Web tests
/// even though we don't currently target web).
class SocketException implements Exception {
  final String message;
  const SocketException(this.message);
  @override
  String toString() => 'SocketException: $message';
}
