import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/sales/widgets/responsive_invoice_section_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSection(
    WidgetTester tester, {
    required double width,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 824));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 824),
            textScaler: const TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: ResponsiveInvoiceSectionCard(
              icon: Icons.shopping_basket_outlined,
              title: 'Productos y servicios',
              trailing: SizedBox(
                key: const ValueKey('bike-selector'),
                height: 48,
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text('GT Outpost'),
                ),
              ),
              children: const [
                SizedBox(
                  key: ValueKey('invoice-section-content'),
                  height: 120,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [384.0, 599.0]) {
    testWidgets('stacks the phone trailing control without overflow at $width',
        (tester) async {
      await pumpSection(tester, width: width);

      expect(
        find.byKey(const ValueKey('invoice-section-phone-trailing')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('bike-selector'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('invoice-section-phone-trailing')),
            )
            .width,
        greaterThan(width - 80),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [600.0, 899.0, 900.0, 1440.0]) {
    testWidgets('keeps the trailing control inline at $width', (tester) async {
      await pumpSection(tester, width: width);

      expect(
        find.byKey(const ValueKey('invoice-section-phone-trailing')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('bike-selector')), findsOneWidget);
      expect(find.text('Productos y servicios'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
