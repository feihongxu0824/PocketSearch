import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvec_photo_search/services/vector_store.dart';
import 'package:zvec_photo_search/ui/widgets/photo_grid.dart';

void main() {
  testWidgets('PhotoGrid renders a tile for each result and shows score',
      (tester) async {
    // zvec MetricType.cosine returns DISTANCE (lower = more similar). The
    // grid displays it as a similarity-feel percentage via (1 - score) * 100,
    // so a score of 0.91 renders as 9%, 0.57 as 43%, 0.12 as 88%.
    final results = [
      PhotoSearchResult(photoId: 'a', photoPath: '/no/such/a.jpg', score: 0.91),
      PhotoSearchResult(photoId: 'b', photoPath: '/no/such/b.jpg', score: 0.57),
      PhotoSearchResult(photoId: 'c', photoPath: '/no/such/c.jpg', score: 0.12),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PhotoGrid(results: results)),
    ));
    // Let image error builders resolve
    await tester.pump();

    // Score labels rendered as (1 - distance) * 100 percentages
    expect(find.text('9%'), findsOneWidget);
    expect(find.text('43%'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);

    // GridView present
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('PhotoGrid with empty results renders no tiles', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PhotoGrid(results: [])),
    ));
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
