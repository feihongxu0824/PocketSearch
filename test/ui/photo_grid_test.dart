import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsearch/services/vector_store.dart';
import 'package:pocketsearch/ui/widgets/photo_grid.dart';

void main() {
  testWidgets('PhotoGrid renders a tile for each result', (tester) async {
    final results = [
      PhotoSearchResult(photoId: 'a', photoPath: '/no/such/a.jpg', score: 0.91),
      PhotoSearchResult(photoId: 'b', photoPath: '/no/such/b.jpg', score: 0.57),
      PhotoSearchResult(photoId: 'c', photoPath: '/no/such/c.jpg', score: 0.12),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PhotoGrid(results: results)),
      ),
    );
    // Let image error builders resolve
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(GestureDetector), findsNWidgets(3));
    expect(find.byType(ClipRRect), findsNWidgets(3));
  });

  testWidgets('PhotoGrid with empty results renders no tiles', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PhotoGrid(results: [])),
      ),
    );
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });
}
