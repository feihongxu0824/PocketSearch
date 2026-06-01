import 'package:flutter/material.dart';

enum PersonalSourceType { reminder, calendar, file }

extension PersonalSourceTypeLabel on PersonalSourceType {
  String get label => switch (this) {
    PersonalSourceType.reminder => 'Reminder',
    PersonalSourceType.calendar => 'Calendar',
    PersonalSourceType.file => 'File',
  };

  IconData get icon => switch (this) {
    PersonalSourceType.reminder => Icons.check_circle_outline_rounded,
    PersonalSourceType.calendar => Icons.event_note_rounded,
    PersonalSourceType.file => Icons.description_outlined,
  };

  static PersonalSourceType parse(String raw) => switch (raw) {
    'reminder' => PersonalSourceType.reminder,
    'calendar' => PersonalSourceType.calendar,
    'file' => PersonalSourceType.file,
    _ => PersonalSourceType.file,
  };
}

class PersonalSourceDocument {
  final String id;
  final PersonalSourceType sourceType;
  final String title;
  final String body;
  final String sourceName;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime indexedAt;
  final String? uri;
  final Map<String, Object?> metadata;

  const PersonalSourceDocument({
    required this.id,
    required this.sourceType,
    required this.title,
    required this.body,
    required this.sourceName,
    required this.indexedAt,
    this.startAt,
    this.endAt,
    this.uri,
    this.metadata = const {},
  });

  String get searchableText => '$title\n$body\n$sourceName';

  factory PersonalSourceDocument.fromMap(Map<dynamic, dynamic> map) {
    DateTime? msToDate(dynamic value) {
      if (value is int && value > 0) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return null;
    }

    return PersonalSourceDocument(
      id: (map['id'] ?? '').toString(),
      sourceType: PersonalSourceTypeLabel.parse(
        (map['sourceType'] ?? 'file').toString(),
      ),
      title: (map['title'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      sourceName: (map['sourceName'] ?? '').toString(),
      indexedAt: msToDate(map['indexedAt']) ?? DateTime.now(),
      startAt: msToDate(map['startAt']),
      endAt: msToDate(map['endAt']),
      uri: map['uri']?.toString(),
      metadata: Map<String, Object?>.from(map['metadata'] as Map? ?? const {}),
    );
  }
}

class TextSearchResult {
  final PersonalSourceDocument document;
  final double score;
  final String snippet;
  final List<TextRange> highlightRanges;
  final List<String> matchedFields;

  const TextSearchResult({
    required this.document,
    required this.score,
    required this.snippet,
    required this.highlightRanges,
    required this.matchedFields,
  });
}
