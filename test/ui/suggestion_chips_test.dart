import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketsearch/ui/widgets/suggestion_chips.dart';

void main() {
  testWidgets('SuggestionChips renders 8 suggestions and fires onTap', (
    tester,
  ) async {
    String? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SuggestionChips(onTap: (q) => tapped = q)),
      ),
    );

    // Should render exactly 8 tappable suggestion chips.
    final chipFinder = find.byType(GestureDetector);
    expect(chipFinder, findsNWidgets(8));

    // Tap the first chip and verify the callback fires with a non-empty query
    await tester.tap(chipFinder.first);
    await tester.pump();
    expect(tapped, isNotNull);
    expect(tapped!.isNotEmpty, isTrue);
  });

  testWidgets('SuggestionChips shows the hint text and footer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SuggestionChips(onTap: (_) {})),
      ),
    );

    expect(find.text('Try searching for...'), findsOneWidget);
    expect(find.textContaining('Powered by zvec'), findsOneWidget);
  });
}
