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
      expect(hubGuidePartsForField('hub_spoke_head_interface'), isNull);
      expect(hubGuidePartsForField('hub_thru_axle_supplied'), isNull);
      expect(hubGuidePartsForField('hub_supplied_thru_axle_reference'), isNull);
    });

    test('a tapped part opens the first field that lights it', () {
      expect(hubGuideFieldForPart(HubGuidePart.old), 'hub_old_mm');
      expect(
          hubGuideFieldForPart(HubGuidePart.pcdRight), 'flange_pcd_right_mm');
      expect(hubGuideFieldForPart(HubGuidePart.axleBody),
          'hub_axle_diameter_datum');
      expect(hubGuideFieldForPart(HubGuidePart.driveReceiver),
          'hub_drive_receiver_present');
      for (final part in HubGuidePart.values) {
        expect(hubGuideFieldForPart(part), isNotNull, reason: part.name);
      }
    });
  });

  group('HubGuideConfiguration', () {
    test('front hub suppresses a stale rear-drive receiver', () {
      final configuration = HubGuideConfiguration.fromSpecValues(const {
        'hub_package_position': 'Delantera',
        'hub_drive_receiver_present': true,
        'hub_drive_receiver_kind': 'Núcleo de cassette',
        'hub_rotor_mount_present': true,
        'rotor_mount_type': 'Centerlock',
        'bearing_system': 'Bolas sueltas',
        'hub_axle_mount_kind': 'Cierre rápido',
      });

      expect(configuration.position, HubGuidePosition.front);
      expect(configuration.driveInterface, HubGuideDriveInterface.none);
      expect(configuration.rotorInterface, HubGuideRotorInterface.centerLock);
      expect(configuration.bearingSystem, HubGuideBearingSystem.loose);
      expect(configuration.axleMount, HubGuideAxleMount.quickRelease);
      expect(configuration.semanticLabel, contains('maza delantera'));
      expect(configuration.semanticLabel, contains('sin montaje para piñón'));
      expect(configuration.semanticLabel, contains('cierre rápido'));
    });

    test('rear cassette and threaded freewheel remain different drawings', () {
      HubGuideConfiguration configuration(String kind) =>
          HubGuideConfiguration.fromSpecValues({
            'hub_package_position': 'Trasera',
            'hub_drive_receiver_present': true,
            'hub_drive_receiver_kind': kind,
            'hub_rotor_mount_present': true,
            'rotor_mount_type': '6 pernos',
            'bearing_system': 'Sellados',
            'hub_axle_mount_kind': 'Eje pasante',
          });

      expect(configuration('Núcleo de cassette').driveInterface,
          HubGuideDriveInterface.cassette);
      expect(configuration('Rosca para piñón (rueda libre)').driveInterface,
          HubGuideDriveInterface.threadedFreewheel);
      expect(configuration('Núcleo de cassette').rotorInterface,
          HubGuideRotorInterface.sixBolt);
      expect(configuration('Núcleo de cassette').bearingSystem,
          HubGuideBearingSystem.sealed);
      expect(configuration('Núcleo de cassette').axleMount,
          HubGuideAxleMount.thruAxle);
    });

    test('unknown prerequisites never invent optional hardware', () {
      const neutral = HubGuideConfiguration();
      final pair = HubGuideConfiguration.fromSpecValues(const {
        'hub_package_position': 'Juego (delantera y trasera)',
        'hub_drive_receiver_present': true,
        'hub_drive_receiver_kind': 'Driver BMX',
        'hub_rotor_mount_present': true,
        'rotor_mount_type': '6 pernos',
        'bearing_system': 'Sellados',
      });

      expect(neutral.driveInterface, HubGuideDriveInterface.unknown);
      expect(neutral.rotorInterface, HubGuideRotorInterface.unknown);
      expect(neutral.bearingSystem, HubGuideBearingSystem.unknown);
      expect(neutral.axleMount, HubGuideAxleMount.unknown);
      expect(pair.isPackageSet, isTrue);
      expect(pair.driveInterface, HubGuideDriveInterface.unknown);
      expect(pair.rotorInterface, HubGuideRotorInterface.unknown);
      expect(pair.bearingSystem, HubGuideBearingSystem.unknown);
      expect(pair.axleMount, HubGuideAxleMount.unknown);
    });
  });

  group('HubMeasureGuidePanel', () {
    Widget host(Widget child) => MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: SizedBox(
                width: 340, child: SingleChildScrollView(child: child)),
          ),
        );

    String label(String key) => switch (key) {
          'hub_old_mm' => 'Ancho de la maza entre apoyos (OLD)',
          'flange_pcd_left_mm' => 'Diámetro del círculo de hoyos izquierdo',
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
      expect(find.text('Ancho de la maza entre apoyos (OLD)'), findsWidgets);
      expect(find.text('De tuerca a tuerca del eje.'), findsOneWidget);
      expect(find.byType(HubMeasureGuide), findsOneWidget);
    });

    testWidgets(
        'lists only the measures the sheet shows, and selecting one reports it',
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
      await tester
          .tap(find.byKey(const ValueKey('hub-guide-chip-flange_pcd_left_mm')));
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
      expect(
          find.text('Este dato no es una medida del dibujo.'), findsOneWidget);
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
      expect(
          find.text('Diámetro del círculo de hoyos izquierdo'), findsWidgets);
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
                highlightedKey: 'hub_old_mm',
                onFieldTap: (key) => tapped = key,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // The focused OLD dimension is drawn under the axle, centred on the
      // over-locknut span (design units 165..835 at y 505 of 1000×600).
      final box = tester.getRect(find.byType(HubMeasureGuide));
      final scale = box.width / 1000;
      await tester.tapAt(box.topLeft + Offset(500 * scale, 505 * scale));
      await tester.pumpAndSettle();
      expect(tapped, 'hub_old_mm');
    });

    testWidgets('a visible attachment wins over the axle behind it',
        (tester) async {
      String? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 1000,
            child: HubMeasureGuide(
              highlightedKey: 'hub_old_mm',
              configuration: const HubGuideConfiguration(
                position: HubGuidePosition.rear,
                rotorInterface: HubGuideRotorInterface.sixBolt,
                driveInterface: HubGuideDriveInterface.threadedFreewheel,
                axleMount: HubGuideAxleMount.quickRelease,
              ),
              onFieldTap: (key) => tapped = key,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(HubMeasureGuide));
      final scale = box.width / 1000;
      await tester.tapAt(box.topLeft + Offset(720 * scale, 310 * scale));
      await tester.pumpAndSettle();

      expect(tapped, 'hub_drive_receiver_present');
    });

    testWidgets('semantics describe only the confirmed hub configuration',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: HubMeasureGuide(
          configuration: HubGuideConfiguration.fromSpecValues(const {
            'hub_package_position': 'Delantera',
            'hub_rotor_mount_present': true,
            'rotor_mount_type': 'Centerlock',
            'hub_drive_receiver_present': false,
            'bearing_system': 'Bolas sueltas',
            'hub_axle_mount_kind': 'Cierre rápido',
          }),
          spokeHoleCount: 8,
        ),
      ));

      expect(
          find.bySemanticsLabel(RegExp(
              'maza delantera.*Centerlock.*sin montaje para piñón.*bolas sueltas.*cierre rápido')),
          findsOneWidget);
    });
  });
}
