// Renders the hub measure guide to PNG files for a visual check without
// driving the live app. Runs only when HUB_GUIDE_RENDER_DIR is set:
//   HUB_GUIDE_RENDER_DIR=/tmp/out flutter test test/unit/hub_measure_guide_render_probe_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/widgets/hub_measure_guide.dart';

void main() {
  final outDir = Platform.environment['HUB_GUIDE_RENDER_DIR'];

  testWidgets('render probe', (tester) async {
    if (outDir == null) return;
    // Real glyphs instead of the test font's boxes, so labels can be judged.
    await tester.runAsync(() async {
      const candidates = [
        '/System/Library/Fonts/Supplemental/Arial.ttf',
        '/System/Library/Fonts/Supplemental/Helvetica.ttf',
      ];
      for (final path in candidates) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final loader = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
        await loader.load();
        break;
      }
    });

    const cases = <(String, String?, double)>[
      ('dialog-idle', null, 960),
      ('dialog-old', 'hub_old_mm', 960),
      ('dialog-pcd-der', 'flange_pcd_right_mm', 960),
      ('dialog-centro-izq', 'center_to_flange_left_mm', 960),
      ('dialog-nucleo', 'hub_drive_receiver_kind', 960),
      ('dialog-rodamientos', 'bearing_system', 960),
      ('sidebar-idle', null, 300),
      ('sidebar-old', 'hub_old_mm', 300),
      ('sidebar-hoyo', 'spoke_hole_diameter_mm', 300),
    ];
    for (final (name, key, width) in [
      ...cases,
      ('dark-dialog-old', 'hub_old_mm', 960.0),
      ('dark-sidebar-pcd', 'flange_pcd_left_mm', 300.0),
    ]) {
      final dark = name.startsWith('dark-');
      final boundaryKey = GlobalKey();
      await tester.binding.setSurfaceSize(Size(width + 40, width * 0.6 + 40));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Roboto',
            brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: Container(
                color: dark ? const Color(0xFF1B1B1F) : Colors.white,
                width: width,
                child: HubMeasureGuide(
                  highlightedKey: key,
                  spokeHoleCount: 36,
                  onFieldTap: (_) {},
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    // The sidebar panel as the form shows it: drawing, current field, button.
    final panelKey = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(360, 520));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
      home: Scaffold(
        body: RepaintBoundary(
          key: panelKey,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: HubMeasureGuidePanel(
              highlightedKey: 'center_to_flange_left_mm',
              labelFor: (key) => switch (key) {
                'center_to_flange_left_mm' => 'Del centro a la brida izquierda',
                _ => key,
              },
              helperFor: (_) =>
                  'Desde el centro de la maza (la mitad del ancho entre tuercas) hasta el centro de la brida izquierda.',
              availableKeys: hubGuideFieldKeys,
              spokeHoleCount: 36,
              onSelect: (_) {},
              onExpand: () {},
              showChips: false,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          panelKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$outDir/panel-sidebar.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.binding.setSurfaceSize(null);
  });
}
