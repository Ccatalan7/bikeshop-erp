import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_scanner/main.dart'; // Correct import

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Mock SharedPreferences to avoid initialization errors
    SharedPreferences.setMockInitialValues({});

    // Build our app and trigger a frame.
    await tester.pumpWidget(const VinabikeScannerApp());

    // Verify that the app builds and shows a scaffold (Waiting or Pairing screen)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
