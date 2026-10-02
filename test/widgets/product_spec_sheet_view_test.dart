import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/public_product_spec_sheet.dart';
import 'package:vinabike_erp/public_store/widgets/product_spec_sheet_view.dart';

Widget _host(Widget child, {double width = 1200}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

PublicProductSpecSheet _tomahawk() => PublicProductSpecSheet.build(
      rows: const [
        PublicProductSpecRow(
            sectionKey: 'measurement',
            key: 'bead_seat_diameter_mm',
            label: 'Aro',
            value: '584',
            unit: 'mm',
            dataType: 'number',
            highlightRank: 1),
        PublicProductSpecRow(
            sectionKey: 'measurement',
            key: 'tire_width_mm',
            label: 'Ancho',
            value: '58.4',
            unit: 'mm',
            dataType: 'number',
            highlightRank: 2),
        PublicProductSpecRow(
            sectionKey: 'primary',
            key: 'tire_tpi',
            label: 'TPI',
            value: '60',
            unit: 'TPI',
            dataType: 'number',
            hint: 'Hilos por pulgada de la carcasa: más TPI, más flexible y '
                'liviano.'),
        PublicProductSpecRow(
            sectionKey: 'declaration',
            key: 'tire_use',
            label: 'Uso',
            value: 'MTB',
            highlightRank: 3),
      ],
      identity: const PublicSpecIdentity(brand: 'Maxxis', model: 'Tomahawk'),
    );

void main() {
  testWidgets('what decides the purchase sits in one object by the price',
      (tester) async {
    var scrolled = false;
    await tester.pumpWidget(_host(
      ProductSpecHighlights(
        items: _tomahawk().highlights,
        onSeeAll: () => scrolled = true,
      ),
      width: 343,
    ));
    expect(find.text('27.5" / 650b'), findsOneWidget);
    expect(find.text('2.3" · 58 mm'), findsOneWidget);
    expect(find.text('MTB'), findsOneWidget);
    // Two cells per row on a phone; the odd third takes the whole row.
    final aro = tester.getRect(find.text('27.5" / 650b'));
    final ancho = tester.getRect(find.text('2.3" · 58 mm'));
    final uso = tester.getRect(find.text('MTB'));
    expect(aro.top, ancho.top);
    expect(uso.top, greaterThan(aro.bottom));
    await tester.tap(find.byKey(const ValueKey('product-spec-see-all')));
    expect(scrolled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the sheet explains its terms, says where data comes from and '
      'offers a person to ask', (tester) async {
    var asked = false;
    await tester.pumpWidget(_host(
      ProductSpecSheetView(
        sheet: _tomahawk(),
        isLoading: false,
        isMobile: false,
        onAsk: () => asked = true,
        askLabel: 'Preguntar por WhatsApp',
      ),
    ));
    expect(find.text('MEDIDAS'), findsOneWidget);
    expect(find.text('CARACTERÍSTICAS'), findsOneWidget);
    expect(find.text('MARCA Y MODELO'), findsOneWidget);
    expect(find.text('ISO 584'), findsOneWidget);
    expect(
        find.text('Hilos por pulgada de la carcasa: más TPI, más flexible y '
            'liviano.'),
        findsOneWidget);
    expect(
        find.text('Ficha preparada por nuestro equipo con información del '
            'fabricante y del proveedor.'),
        findsOneWidget);
    expect(find.text('¿Le sirve a tu bicicleta?'), findsOneWidget);
    await tester.tap(find.text('Preguntar por WhatsApp'));
    expect(asked, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a product without technical data offers help, not an apology, phone width',
      (tester) async {
    await tester.pumpWidget(_host(
      ProductSpecSheetView(
        sheet: PublicProductSpecSheet.build(
          rows: const [],
          identity: const PublicSpecIdentity(brand: 'KMC'),
        ),
        isLoading: false,
        isMobile: true,
        onAsk: () {},
      ),
      width: 343,
    ));
    // A product without technical data is not announced as missing one.
    expect(find.textContaining('Aún no publicamos'), findsNothing);
    expect(find.textContaining('Ficha preparada'), findsNothing);
    expect(find.text('¿Le sirve a tu bicicleta?'), findsNothing);
    expect(find.text('¿Tienes una duda?'), findsOneWidget);
    expect(find.text('Escríbenos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
