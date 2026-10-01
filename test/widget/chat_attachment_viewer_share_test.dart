import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_attachment_viewer.dart';
import 'package:vinabike_erp/shared/utils/file_share.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El visor de adjuntos ofrece «Compartir» (menú del sistema) y cabe en un
/// teléfono: zoom, imprimir, descargar, abrir y cerrar sumaban ~400 px en un
/// diálogo de 366. Su encabezado se lee en claro y en oscuro: con el fondo
/// fijo en claro, el oscuro pintaba las acciones gris claro sobre blanco.
void main() {
  // PNG transparente de 1×1.
  const pngDataUrl = 'data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==';

  // El gate corre en Linux, sin menú Compartir: se fija como en un teléfono.
  setUp(() => debugCanShareFilesOverride = true);
  tearDown(() => debugCanShareFilesOverride = null);

  Future<void> open(
    WidgetTester tester,
    double width, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike,
          brightness: brightness,
        ),
        home: const Scaffold(
          body: ChatAttachmentViewer(
            url: pngDataUrl,
            fileName: 'IMG_20260929_101512.png',
            extension: 'png',
            contentType: 'image/png',
            isImage: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('en teléfono: Compartir a la vista, lo demás en «Más acciones»',
      (tester) async {
    await open(tester, 390);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Compartir'), findsOneWidget);
    expect(find.byTooltip('Más acciones'), findsOneWidget);
    expect(find.byTooltip('Guardar en Archivos y descargar'), findsNothing);

    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    expect(find.text('Imprimir'), findsOneWidget);
    expect(find.text('Guardar en Archivos'), findsOneWidget);
    expect(find.text('Abrir externo'), findsOneWidget);
  });

  testWidgets('en escritorio conserva la barra completa y suma Compartir',
      (tester) async {
    await open(tester, 1280);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Compartir'), findsOneWidget);
    expect(find.byTooltip('Guardar en Archivos y descargar'), findsOneWidget);
    expect(find.byTooltip('Abrir externo'), findsOneWidget);
    expect(find.byTooltip('Más acciones'), findsNothing);
  });

  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  Color painted(WidgetTester tester, Finder icon) => tester
      .widget<RichText>(
          find.descendant(of: icon, matching: find.byType(RichText)))
      .text
      .style!
      .color!;

  for (final brightness in Brightness.values) {
    testWidgets('el encabezado se lee en ${brightness.name}', (tester) async {
      await open(tester, 390, brightness: brightness);
      final header = tester
          .widget<Container>(
              find.byKey(const ValueKey('chat-attachment-header')))
          .color!;

      for (final tooltip in ['Compartir', 'Más acciones', 'Cerrar']) {
        final icon = find.descendant(
            of: find.byTooltip(tooltip), matching: find.byType(Icon));
        expect(
            contrast(painted(tester, icon), header), greaterThanOrEqualTo(3.0),
            reason: '«$tooltip» en ${brightness.name}');
      }
      final title = tester.widget<Text>(find.text('IMG_20260929_101512.png'));
      expect(contrast(title.style!.color!, header), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('sin menú Compartir en el sistema no se ofrece el botón',
      (tester) async {
    debugCanShareFilesOverride = false;
    await open(tester, 390);
    expect(find.byTooltip('Compartir'), findsNothing);
    expect(find.byTooltip('Más acciones'), findsOneWidget);
  });
}
