import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/widgets/hub_measure_guide.dart';

void main() {
  group('hub guide mapping', () {
    test('every hub measurement the sheet asks for has a place on the drawing',
        () {
      const measurements = [
        'hub_old_mm',
        'hub_flange_to_flange_mm',
        'center_to_flange_left_mm',
        'center_to_flange_right_mm',
        'flange_pcd_left_mm',
        'flange_pcd_right_mm',
        'spoke_hole_diameter_mm',
        'spoke_hole_count',
        'hub_axle_diameter_mm',
        'hub_axle_diameter_datum',
        'rotor_mount_type',
        'hub_drive_receiver_reference',
      ];
      for (final key in measurements) {
        expect(hubGuidePartsForField(key), isNotNull, reason: key);
        expect(hubGuidePartsForField(key), isNotEmpty, reason: key);
        expect(hubGuideFieldKeys, contains(key), reason: key);
      }
    });

    test('fields that are not a measure of the drawing map to nothing', () {
      expect(hubGuidePartsForField('hub_package_position'), isNull);
      expect(hubGuidePartsForField('spec_evidence_source'), isNull);
      expect(hubGuidePartsForField('hub_package_pieces'), isNull);
    });

    test('a tapped part opens the first field that lights it', () {
      expect(hubGuideFieldForPart(HubGuidePart.old), 'hub_old_mm');
      expect(hubGuideFieldForPart(HubGuidePart.pcdRight), 'flange_pcd_right_mm');
      expect(hubGuideFieldForPart(HubGuidePart.axleBody),
          'hub_axle_diameter_datum');
      expect(hubGuideFieldForPart(HubGuidePart.driveReceiver),
          'hub_drive_receiver_present');
      for (final part in HubGuidePart.values) {
        expect(hubGuideFieldForPart(part), isNotNull, reason: part.name);
      }
    });
  });

  group('HubMeasureGuidePanel', () {
    Widget host(Widget child) => MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: SizedBox(width: 340, child: SingleChildScrollView(child: child)),
          ),
        );

    String label(String key) => switch (key) {
          'hub_old_mm' => 'Ancho entre tuercas (OLD)',
          'flange_pcd_left_mm' => 'Círculo de hoyos, brida izquierda (PCD)',
          _ => key,
        };

    testWidgets('names the field the operator is on and explains it',
        (tester) async {
      await tester.pumpWidget(host(HubMeasureGuidePanel(
        highlightedKey: 'hub_old_mm',
        labelFor: label,
        helperFor: (key) =>
            key == 'hub_old_mm' ? 'De tuerca a tuerca del eje.' : null,
        availableKeys: const ['hub_old_mm', 'flange_pcd_left_mm'],
        onSelect: (_) {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('Ancho entre tuercas (OLD)'), findsWidgets);
      expect(find.text('De tuerca a tuerca del eje.'), findsOneWidget);
      expect(find.byType(HubMeasureGuide), findsOneWidget);
    });

    testWidgets('lists only the measures the sheet shows, and selecting one reports it',
        (tester) async {
      String? selected;
      await tester.pumpWidget(host(HubMeasureGuidePanel(
        highlightedKey: null,
        labelFor: label,
        helperFor: (_) => null,
        availableKeys: const ['hub_old_mm', 'flange_pcd_left_mm'],
        onSelect: (key) => selected = key,
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hub-guide-chip-hub_old_mm')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('hub-guide-chip-flange_pcd_right_mm')),
          findsNothing);
      expect(
          find.text(
              'Toca un campo de la ficha y el dibujo te muestra dónde se mide.'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hub-guide-chip-flange_pcd_left_mm')));
      await tester.pumpAndSettle();
      expect(selected, 'flange_pcd_left_mm');
    });

    testWidgets('a field without a place on the drawing still gets its text',
        (tester) async {
      await tester.pumpWidget(host(HubMeasureGuidePanel(
        highlightedKey: 'hub_package_position',
        labelFor: (key) =>
            key == 'hub_package_position' ? 'Posición de la maza' : key,
        helperFor: (key) =>
            key == 'hub_package_position' ? 'Qué viene en la caja.' : null,
        availableKeys: const ['hub_old_mm'],
        onSelect: (_) {},
      )));
      await tester.pumpAndSettle();
      expect(find.text('Posición de la maza'), findsOneWidget);
      expect(find.text('Este dato no es una medida del dibujo.'), findsOneWidget);
    });

    testWidgets(
        'hovering away and back to a field mid-animation never duplicates keys',
        (tester) async {
      // 2026-09-17: an AnimatedSwitcher keyed by the field put two entries
      // with the same key in its Stack when the highlight returned before the
      // fade ended; the whole editor then failed with «Duplicate keys found».
      Widget panel(String? key) => host(HubMeasureGuidePanel(
            highlightedKey: key,
            labelFor: label,
            helperFor: (_) => null,
            availableKeys: const ['hub_old_mm', 'flange_pcd_left_mm'],
            onSelect: (_) {},
          ));
      await tester.pumpWidget(panel(null));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(panel('hub_old_mm'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(panel(null));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(panel('hub_old_mm'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(panel('flange_pcd_left_mm'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Círculo de hoyos, brida izquierda (PCD)'), findsWidgets);
    });

    testWidgets('tapping a drawn dimension reports its field', (tester) async {
      String? tapped;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1000,
              child: HubMeasureGuide(
                highlightedKey: null,
                onFieldTap: (key) => tapped = key,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // The OLD dimension is drawn under the axle, centred on the drawing's
      // over-locknut span (design units 158..572 at y 494 of 1000×600).
      final box = tester.getRect(find.byType(HubMeasureGuide));
      final scale = box.width / 1000;
      await tester.tapAt(box.topLeft + Offset(365 * scale, 494 * scale));
      await tester.pumpAndSettle();
      expect(tapped, 'hub_old_mm');
    });
  });
}
