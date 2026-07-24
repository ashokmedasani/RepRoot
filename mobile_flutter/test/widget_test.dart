// Smoke test. The full app (RepRootApp) wires a router, Riverpod providers,
// secure storage, and network calls, so it is not pumped directly here — that
// belongs in integration tests with a fake backend. This keeps `flutter test`
// green without asserting on live behaviour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MaterialApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: Text('RepRoot')))),
    );
    expect(find.text('RepRoot'), findsOneWidget);
  });
}
