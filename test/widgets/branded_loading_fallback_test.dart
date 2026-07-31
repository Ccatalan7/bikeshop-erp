import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/widgets/branded_loading.dart';

void main() {
  testWidgets('loading stays visible when no branded logo is available',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BrandedLoading(
            size: 48,
            animate: false,
            message: 'Cargando',
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('branded-loading-fallback')),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Cargando'), findsOneWidget);
  });
}
