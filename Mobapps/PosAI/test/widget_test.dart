// Basic widget test for POS AI

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_ai/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PosAIApp());

    // Verify app loads - splash screen should appear
    await tester.pump();

    // Basic smoke test - app should load without crashing
    expect(find.byType(PosAIApp), findsOneWidget);
  });
}
