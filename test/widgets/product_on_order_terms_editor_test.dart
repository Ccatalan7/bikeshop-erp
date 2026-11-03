import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/product_on_order_terms_service.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_on_order_terms_editor.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// «Se vende a pedido» en la ficha del producto (product_on_order_terms):
/// el interruptor, el proveedor y el plazo, con lo que dirá la tienda.
void main() {
  test('only what changed is saved; off and never saved writes nothing', () {
    const saved = ProductOnOrderTerms(
      isActive: true,
      leadDaysMin: 3,
      leadDaysMax: 5,
      supplierId: 'sup-1',
    );

    expect(
        ProductOnOrderTerms.changeBetween(
            ProductOnOrderTerms.off, ProductOnOrderTerms.off),
        isNull);
    expect(ProductOnOrderTerms.changeBetween(saved, saved), isNull);
    expect(
      ProductOnOrderTerms.changeBetween(
        saved,
        const ProductOnOrderTerms(
            isActive: false,
            leadDaysMin: 3,
            leadDaysMax: 5,
            supplierId: 'sup-1'),
      )?.isActive,
      isFalse,
      reason: 'turning it off is saved',
    );
    expect(
      ProductOnOrderTerms.changeBetween(
        ProductOnOrderTerms.off,
        const ProductOnOrderTerms(
            isActive: true,
            leadDaysMin: 7,
            leadDaysMax: 10,
            supplierId: 'sup-1'),
      )?.leadLabel,
      'llega en 7 a 10 días hábiles',
    );
  });

  test('the days follow the bounds the database keeps', () {
    expect(ProductOnOrderTermsEditor.validateMin(''), 'Escribe los días.');
    expect(ProductOnOrderTermsEditor.validateMin('121'), 'Entre 0 y 120 días.');
    expect(ProductOnOrderTermsEditor.validateMin('3'), isNull);
    expect(ProductOnOrderTermsEditor.validateMax('2', '3'),
        'No puede ser menos que el mínimo.');
    expect(
        ProductOnOrderTermsEditor.validateMax('181', '3'), 'Hasta 180 días.');
    expect(ProductOnOrderTermsEditor.validateMax('5', '3'), isNull);
  });

  testWidgets(
      'on, it asks who brings it and in how many working days, and '
      'says what the store will show', (tester) async {
    final min = TextEditingController(text: '3');
    final max = TextEditingController(text: '5');
    addTearDown(min.dispose);
    addTearDown(max.dispose);
    var active = false;
    String? supplier = 'sup-1';

    Future<void> pump() => tester.pumpWidget(MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Padding(
                padding: const EdgeInsets.all(16),
                child: ProductOnOrderTermsEditor(
                  active: active,
                  onActiveChanged: (value) => setState(() => active = value),
                  suppliers: const [
                    (id: 'sup-1', name: 'TeknoBike'),
                    (id: 'sup-2', name: 'Bicicletas Oxford'),
                  ],
                  supplierId: supplier,
                  onSupplierChanged: (value) =>
                      setState(() => supplier = value),
                  minController: min,
                  maxController: max,
                ),
              ),
            ),
          ),
        ));
    await pump();

    expect(find.text('Se vende a pedido'), findsOneWidget);
    expect(find.textContaining('la tienda lo muestra agotado'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('product-on-order-supplier')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('product-on-order-switch')));
    await tester.pumpAndSettle();
    expect(active, isTrue);
    expect(find.text('TeknoBike'), findsOneWidget);
    expect(find.text('En la tienda: «A pedido · llega en 3 a 5 días hábiles».'),
        findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('product-on-order-max')), '10');
    await tester.pump();
    expect(
        find.text('En la tienda: «A pedido · llega en 3 a 10 días hábiles».'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('what could not be read is not overwritten', (tester) async {
    final min = TextEditingController(text: '3');
    final max = TextEditingController(text: '5');
    addTearDown(min.dispose);
    addTearDown(max.dispose);
    var toggled = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: ProductOnOrderTermsEditor(
          active: false,
          onActiveChanged: (_) => toggled = true,
          suppliers: const [],
          supplierId: null,
          onSupplierChanged: (_) {},
          minController: min,
          maxController: max,
          loadError: 'No se pudo leer si se vende a pedido.',
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('product-on-order-switch')));
    await tester.pump();
    expect(toggled, isFalse);
    expect(find.text('No se pudo leer si se vende a pedido.'), findsOneWidget);
  });
}
