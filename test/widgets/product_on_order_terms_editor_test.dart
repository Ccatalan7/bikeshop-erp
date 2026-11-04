import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/product_on_order_terms_service.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_on_order_terms_editor.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// «Cuando no hay stock» en la ficha del producto (product_on_order_terms):
/// según la marca, se cotiza, a pedido (con proveedor y plazo, y lo que dirá
/// la tienda) o no se ofrece (20261103070000).
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

  test('the decision without stock is the form\'s, or else the brand\'s', () {
    const saved = ProductOnOrderTerms(
      isActive: true,
      leadDaysMin: 7,
      leadDaysMax: 10,
      supplierId: 'sup-1',
    );
    expect(saved.offer, SoldOutOffer.onOrder);
    expect(ProductOnOrderTerms.off.offer, SoldOutOffer.byBrand);

    final quoted = saved.withOffer(SoldOutOffer.quote);
    expect(quoted.offer, SoldOutOffer.quote);
    expect(quoted.isActive, isFalse);
    expect(quoted.supplierId, 'sup-1',
        reason: 'the supplier and lead time wait for the next time on order');
    expect(quoted.leadLabel, 'llega en 7 a 10 días hábiles');
    expect(saved.withOffer(SoldOutOffer.none).quoteWhenSoldOut, isFalse);
    expect(saved.withOffer(SoldOutOffer.byBrand).quoteWhenSoldOut, isNull);
    expect(quoted.withOffer(SoldOutOffer.onOrder).quoteWhenSoldOut, isNull);

    expect(
      ProductOnOrderTerms.changeBetween(
        ProductOnOrderTerms.off,
        ProductOnOrderTerms.off.withOffer(SoldOutOffer.none),
      )?.quoteWhenSoldOut,
      isFalse,
      reason: '«No se ofrece» is saved even though it never sold on order',
    );
    expect(
      ProductOnOrderTerms.changeBetween(
        ProductOnOrderTerms.off,
        const ProductOnOrderTerms(
            isActive: false, leadDaysMin: 9, leadDaysMax: 12),
      ),
      isNull,
      reason: 'by brand, the lead time alone writes nothing',
    );
    expect(
      ProductOnOrderTerms.fromJson(const {
        'is_active': false,
        'lead_days_min': 3,
        'lead_days_max': 5,
        'quote_when_sold_out': true,
      }).offer,
      SoldOutOffer.quote,
    );
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    required SoldOutOffer Function() offer,
    required ValueChanged<SoldOutOffer> onOfferChanged,
    required TextEditingController min,
    required TextEditingController max,
    String? brandName = 'Pedalia',
    bool brandQuoted = true,
    String? loadError,
  }) =>
      tester.pumpWidget(MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ProductOnOrderTermsEditor(
                offer: offer(),
                onOfferChanged: (value) =>
                    setState(() => onOfferChanged(value)),
                brandName: brandName,
                brandQuoted: brandQuoted,
                suppliers: const [
                  (id: 'sup-1', name: 'TeknoBike'),
                  (id: 'sup-2', name: 'Bicicletas Oxford'),
                ],
                supplierId: 'sup-1',
                onSupplierChanged: (_) {},
                minController: min,
                maxController: max,
                loadError: loadError,
              ),
            ),
          ),
        ),
      ));

  testWidgets(
      'it says what the brand decides, and on order it asks who brings it '
      'and in how many working days', (tester) async {
    final min = TextEditingController(text: '3');
    final max = TextEditingController(text: '5');
    addTearDown(min.dispose);
    addTearDown(max.dispose);
    var offer = SoldOutOffer.byBrand;

    await pumpEditor(tester,
        offer: () => offer,
        onOfferChanged: (value) => offer = value,
        min: min,
        max: max);

    expect(find.text('Cuando no hay stock'), findsOneWidget);
    expect(find.text('Pedalia se cotiza sin stock.'), findsOneWidget);
    expect(find.text('Se cotiza'), findsOneWidget);
    expect(find.text('No se ofrece'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('product-on-order-supplier')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('product-sold-out-onOrder')));
    await tester.pumpAndSettle();
    expect(offer, SoldOutOffer.onOrder);
    expect(find.text('TeknoBike'), findsOneWidget);
    expect(find.text('En la tienda: «A pedido · llega en 3 a 5 días hábiles».'),
        findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('product-on-order-max')), '10');
    await tester.pump();
    expect(
        find.text('En la tienda: «A pedido · llega en 3 a 10 días hábiles».'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('product-sold-out-none')));
    await tester.pumpAndSettle();
    expect(offer, SoldOutOffer.none);
    expect(
        find.byKey(const ValueKey('product-on-order-supplier')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a brand off the list, or no brand, is not offered',
      (tester) async {
    final min = TextEditingController(text: '3');
    final max = TextEditingController(text: '5');
    addTearDown(min.dispose);
    addTearDown(max.dispose);

    await pumpEditor(tester,
        offer: () => SoldOutOffer.byBrand,
        onOfferChanged: (_) {},
        min: min,
        max: max,
        brandName: 'Ruedex',
        brandQuoted: false);
    expect(
        find.textContaining('Ruedex no está entre las marcas'), findsOneWidget);
    expect(
        find.textContaining('Ventas › Cotizaciones › Ajustes'), findsOneWidget);

    await pumpEditor(tester,
        offer: () => SoldOutOffer.byBrand,
        onOfferChanged: (_) {},
        min: min,
        max: max,
        brandName: '  ',
        brandQuoted: false);
    expect(find.text('Sin marca, no se ofrece.'), findsOneWidget);
  });

  testWidgets('what could not be read is not overwritten', (tester) async {
    final min = TextEditingController(text: '3');
    final max = TextEditingController(text: '5');
    addTearDown(min.dispose);
    addTearDown(max.dispose);
    var changed = false;

    await pumpEditor(tester,
        offer: () => SoldOutOffer.byBrand,
        onOfferChanged: (_) => changed = true,
        min: min,
        max: max,
        loadError: 'No se pudo leer qué hace la tienda sin stock.');

    await tester.tap(find.byKey(const ValueKey('product-sold-out-quote')));
    await tester.pump();
    expect(changed, isFalse);
    expect(find.text('No se pudo leer qué hace la tienda sin stock.'),
        findsOneWidget);
  });
}
