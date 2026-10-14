import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/shipping_zone.dart';
import 'package:vinabike_erp/modules/website/pages/shipping_zones_page.dart';
import 'package:vinabike_erp/modules/website/services/shipping_zones_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

// Invented rates (2026-10-14: shipping by destination zone).
const _zones = [
  ShippingZone(
    name: 'Región de Valparaíso',
    regionCodes: ['CL-VS'],
    bands: [
      ShippingBand(
        minOrderGross: 0,
        maxOrderGross: 30000,
        shippingGross: 5990,
        minDays: 1,
        maxDays: 3,
      ),
      ShippingBand(minOrderGross: 30000, shippingGross: 7990),
    ],
  ),
  ShippingZone(
    name: 'Centro',
    regionCodes: ['CL-RM', 'CL-LI'],
    bands: [ShippingBand(minOrderGross: 0, shippingGross: 7490)],
  ),
];

class _Store implements ShippingZonesStore {
  List<ShippingZone> zones = _zones;
  List<ShippingZone>? saved;

  @override
  Future<List<ShippingZone>> load() async => zones;

  @override
  Future<List<ShippingZone>> save(List<ShippingZone> zones) async {
    saved = zones;
    this.zones = zones;
    return zones;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Store store, {
  Size size = const Size(1280, 1000),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.vinabike,
      brightness: brightness,
    ),
    home: Scaffold(body: ShippingZonesPage(embedded: true, store: store)),
  ));
  await tester.pumpAndSettle();
}

ButtonStyleButton _saveButton(WidgetTester tester) => tester.widget(
      find.byKey(const ValueKey('shipping-zones-save')),
    );

void main() {
  testWidgets('the zones load with their regions and bands', (tester) async {
    await _pump(tester, _Store());

    expect(find.text('Región de Valparaíso'), findsOneWidget);
    expect(find.text('Centro'), findsOneWidget);
    expect(find.text('Desde \$ 0'), findsOneWidget);
    expect(find.text('Desde \$ 0 · sin tope'), findsOneWidget);
    expect(find.textContaining('sin tope'), findsNWidgets(2));
    // Regions in no zone are said, as the checkout will say them.
    expect(find.textContaining('Sin zona: Arica y Parinacota'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull, reason: 'nothing changed');
  });

  testWidgets('a region of another zone cannot be picked twice',
      (tester) async {
    await _pump(tester, _Store());

    final taken = tester.widgetList<FilterChip>(find.byType(FilterChip)).where(
          (chip) =>
              (chip.label as Text).data == 'Metropolitana' && !chip.selected,
        );
    expect(taken, hasLength(1));
    expect(taken.single.onSelected, isNull);
  });

  testWidgets('a new region, a new band and the save', (tester) async {
    final store = _Store();
    await _pump(tester, store);

    // Biobío joins «Centro».
    final biobio = find.widgetWithText(FilterChip, 'Biobío');
    await tester.tap(biobio.last);
    await tester.pumpAndSettle();

    // «Centro» gets a second band: the first one needs its ceiling.
    await tester.ensureVisible(find.text('Agregar tramo').last);
    await tester.tap(find.text('Agregar tramo').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('debe terminar después'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);

    final ceilings = find.widgetWithText(TextField, 'Hasta (sin incluir)');
    await tester.enterText(ceilings.last, '40000');
    await tester.pumpAndSettle();
    expect(find.text('Desde \$ 40.000 · sin tope'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('shipping-zones-save')));
    await tester.pumpAndSettle();

    final centro = store.saved![1];
    expect(centro.regionCodes, ['CL-RM', 'CL-LI', 'CL-BI']);
    expect(centro.bands.map((band) => band.toJson()['max_order_gross']),
        [40000, null]);
    expect(centro.bands.last.minOrderGross, 40000);
    expect(find.textContaining('el checkout ya cobra'), findsOneWidget);
  });

  testWidgets('a zone without regions cannot be saved', (tester) async {
    await _pump(tester, _Store());

    await tester
        .ensureVisible(find.byKey(const ValueKey('shipping-zones-add')));
    await tester.tap(find.byKey(const ValueKey('shipping-zones-add')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Elige al menos una región para «Zona 3»'),
        findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  // 2026-10-14: Correos charged $6.240 for WEB-26-00021 (Viña → Macul,
  // boleta) and the order charged $6.990: the shipment lost $366.
  testWidgets('the rates are calculated from what the carrier charges',
      (tester) async {
    final store = _Store();
    await _pump(tester, store);

    await tester.tap(find.byKey(const ValueKey('shipping-zones-suggest')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('shipping-zones-suggest-cost')),
      '6240',
    );
    await tester.pumpAndSettle();
    expect(find.text('desde \$ 7.490'), findsOneWidget, reason: 'Santiago');
    await tester
        .tap(find.byKey(const ValueKey('shipping-zones-suggest-apply')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('shipping-zones-save')));
    await tester.pumpAndSettle();
    final saved = store.saved!;
    expect(saved.map((zone) => zone.name), [
      'Región de Valparaíso',
      'Santiago',
      'Centro',
      'Sur',
      'Norte',
      'Zona austral',
    ]);
    expect(saved.expand((zone) => zone.regionCodes).toSet(),
        hasLength(chileanShippingRegions.length),
        reason: 'every region has a zone');
    expect(
      saved[1].bands.map((band) => band.shippingGross),
      [7490, 9990, 11990, 15490],
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('on a 360 px phone the zones fit, ${brightness.name}',
        (tester) async {
      await _pump(
        tester,
        _Store(),
        size: const Size(360, 780),
        brightness: brightness,
      );

      expect(find.text('Región de Valparaíso'), findsOneWidget);
      // With a change pending the header carries «Descartar» too.
      final biobio = find.widgetWithText(FilterChip, 'Biobío').first;
      await tester.ensureVisible(biobio);
      await tester.pumpAndSettle();
      await tester.tap(biobio);
      await tester.pumpAndSettle();
      expect(find.text('Descartar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('a carrier cost becomes a price that never loses', () {
    expect(roundUpShippingPrice(7425.6), 7490);
    expect(roundUpShippingPrice(7490), 7490);
    expect(roundUpShippingPrice(7491), 7990);
    final zones = suggestedShippingZones(
      carrierCostToSantiago: 6240,
      paidWithReceipt: true,
    );
    // With a boleta the price leaves the whole cost after the sale's IVA.
    expect(zones[1].bands.first.shippingGross / 1.19, greaterThan(6240));
    expect(shippingZonesProblem(zones), isNull);
    final invoiced = suggestedShippingZones(
      carrierCostToSantiago: 6240,
      paidWithReceipt: false,
    );
    expect(invoiced[1].bands.first.shippingGross, 6490);
  });

  test('the rules the editor checks before saving', () {
    expect(shippingZonesProblem(_zones), isNull);
    expect(shippingZonesProblem(const []), 'Agrega al menos una zona.');
    expect(
      shippingZonesProblem(const [
        ShippingZone(
          name: 'A',
          regionCodes: ['CL-VS'],
          bands: [ShippingBand(minOrderGross: 0, shippingGross: 5990)],
        ),
        ShippingZone(
          name: 'B',
          regionCodes: ['CL-VS'],
          bands: [ShippingBand(minOrderGross: 0, shippingGross: 5990)],
        ),
      ]),
      'Valparaíso está en «A» y en «B».',
    );
    expect(
      shippingZonesProblem(const [
        ShippingZone(
          name: 'A',
          regionCodes: ['CL-VS'],
          bands: [ShippingBand(minOrderGross: 1000, shippingGross: 5990)],
        ),
      ]),
      'Los tramos de «A» deben seguirse sin huecos desde \$0.',
    );
  });
}
