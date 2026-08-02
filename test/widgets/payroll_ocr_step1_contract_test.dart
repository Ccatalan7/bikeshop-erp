import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/pages/payroll_reconciliation_page.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_money_bar.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/utils/responsive_breakpoints.dart';

/// **5j · paso 1 (`Subir cartola`)** — contrato de lo que la pantalla PROMETE.
///
/// Existe porque las promesas de esta pantalla se comprueban leyendo el
/// extractor, no mirando el frame, y dos de ellas ya se colaron una vez: el
/// frame dibuja «hasta 20 MB» cuando el código rechaza sobre 12, y promete una
/// extracción «exacta» y «confianza por línea» que el servicio no garantiza.
/// Una batería verde alrededor no congela nada de eso: hay que nombrarlo.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    Brightness brightness = Brightness.light,
    AppearancePreset? preset,
    bool imageOcr = true,
    bool camera = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: AppTheme.resolve(
          preset: preset ?? AppearancePresets.all.first,
          brightness: brightness,
        ),
        home: Scaffold(
          body: PayrollReconciliationPage(
            actions: PayrollReconciliationActions(
              prepare: (
                      {required bytes, required filename, sourcePath}) async =>
                  throw UnimplementedError(),
              createImport: (draft, {required erpAccountId}) async =>
                  throw UnimplementedError(),
              apply: ({
                required authorizedDraftVoucherIds,
                required decisions,
                required draft,
                required importReceipt,
                operationKey,
              }) async =>
                  throw UnimplementedError(),
              isImageOcrSupported: imageOcr,
              isCameraCaptureSupported: camera,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('las tres expectativas de fuente están, con su disponibilidad',
      (tester) async {
    await pump(tester, size: const Size(1360, 900));

    for (final title in const <String>[
      'PDF del banco',
      'Imagen o captura',
      'Foto con la cámara',
    ]) {
      expect(
        find.byKey(ValueKey<String>('payroll-source-expectation-$title')),
        findsOneWidget,
        reason: 'falta la expectativa de $title',
      );
    }

    // «Cámara» a secas es el rótulo del BOTÓN. Dos cosas distintas no pueden
    // llamarse igual: un lector de pantalla anunciaría dos veces lo mismo.
    expect(find.text('Cámara'), findsOneWidget,
        reason: 'sólo el control de captura se llama «Cámara»');

    // Sin OCR cloud y sin cámara, las tarjetas lo DICEN en vez de desaparecer:
    // un vacío no explica por qué falta la opción.
    await pump(
      tester,
      size: const Size(1360, 900),
      imageOcr: false,
      camera: false,
    );
    expect(
      find.textContaining('No disponible ahora'),
      findsOneWidget,
    );
    expect(find.textContaining('Sólo en Android y iPhone'), findsOneWidget);
  });

  testWidgets('el límite es el del extractor, y ninguna promesa sobreafirma',
      (tester) async {
    await pump(tester, size: const Size(1360, 900));

    // `payroll_statement_extraction_service.dart` rechaza sobre 12 MB. El frame
    // dibuja 20 y ese número mandaría a elegir un archivo que va a fallar.
    expect(find.textContaining('Hasta 12 MB'), findsOneWidget);
    expect(find.textContaining('20 MB'), findsNothing,
        reason: 'el frame dice 20; el extractor rechaza sobre 12');

    // `_needsPdfOcrRetry` fuerza OCR cuando el texto del PDF no se estructura,
    // así que «exacta» es falso.
    expect(find.textContaining('exacta'), findsNothing,
        reason: 'embeddedPdfText es el método inicial, no una garantía');
    expect(
      find.textContaining('no usa OCR cuando viene estructurado'),
      findsOneWidget,
    );

    // El parser lleva las filas dudosas a revisión; no garantiza detectar
    // todo lo ilegible ni da confianza OCR por línea.
    expect(find.textContaining('confianza por línea'), findsNothing);
    expect(
      find.textContaining('filas dudosas quedan señaladas'),
      findsOneWidget,
    );
  });

  testWidgets(
      'la composición cambia con el owner responsivo canónico, sin overflow',
      (tester) async {
    // Teléfono: apiladas. Desde tablet: tres columnas. El corte es
    // `ResponsiveBreakpoints.phoneMaxExclusive`, no un número de esta pantalla.
    for (final size in const <Size>[
      Size(390, 844),
      Size(430, 928),
      Size(834, 1112),
      Size(1360, 900),
    ]) {
      for (final brightness in Brightness.values) {
        await pump(tester, size: size, brightness: brightness);
        final cell = '${size.width.toInt()}/${brightness.name}';
        final first = tester.getRect(
          find.byKey(
            const ValueKey<String>('payroll-source-expectation-PDF del banco'),
          ),
        );
        final second = tester.getRect(
          find.byKey(
            const ValueKey<String>(
              'payroll-source-expectation-Imagen o captura',
            ),
          ),
        );
        // El umbral se cita del owner canónico, no se repite como literal: si
        // `phoneMaxExclusive` se mueve, el contrato se mueve con él.
        if (size.width < ResponsiveBreakpoints.phoneMaxExclusive) {
          expect(second.top, greaterThanOrEqualTo(first.bottom),
              reason: '$cell: en teléfono las tarjetas se apilan');
        } else {
          expect(second.left, greaterThanOrEqualTo(first.right),
              reason: '$cell: desde phoneMaxExclusive van en fila');
          expect(second.height, first.height,
              reason: '$cell: en fila comparten alto');
        }
        expect(tester.takeException(), isNull, reason: '$cell: overflow');
      }
    }
  });

  testWidgets(
      'en teléfono la TERCERA tarjeta se alcanza entera, sobre la barra fija',
      (tester) async {
    // Se afirmó que a 430 «se apilan y el CTA queda visible» y se dio por
    // inspeccionada una tarjeta que en la captura estaba cortada por el pie.
    // Existir en el árbol no es estar al alcance: hay que llevar el scroll
    // hasta ella y comprobar que cabe ENTERA por encima de la barra
    // persistente, que es lo que el operador de teléfono necesita.
    for (final size in const <Size>[Size(390, 844), Size(430, 928)]) {
      for (final brightness in Brightness.values) {
        await pump(tester, size: size, brightness: brightness);
        final cell = '${size.width.toInt()}/${brightness.name}';

        final third = find.byKey(
          const ValueKey<String>(
            'payroll-source-expectation-Foto con la cámara',
          ),
        );
        await tester.scrollUntilVisible(
          third,
          160,
          scrollable: find.descendant(
            of: find.byKey(
              const PageStorageKey<String>('payroll-reconciliation-file'),
            ),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();

        final card = tester.getRect(third);
        final bar = tester.getRect(find.byType(PayrollMoneyBar));
        expect(
          card.bottom,
          lessThanOrEqualTo(bar.top),
          reason: '$cell: la tercera tarjeta queda bajo la barra persistente',
        );
        expect(card.top, greaterThanOrEqualTo(0),
            reason: '$cell: se sale por arriba del viewport');
        expect(tester.takeException(), isNull, reason: cell);
      }
    }
  });

  testWidgets('el aviso de modo revisión se ve ANTES de elegir archivo',
      (tester) async {
    // Quien no va a poder aplicar tiene que saberlo antes de gastar el gesto.
    await pump(tester, size: const Size(390, 844));
    final notice = find.byKey(
      const ValueKey('payroll-reconciliation-backend-missing'),
    );
    if (notice.evaluate().isEmpty) return;
    expect(
      tester.getRect(notice).top,
      lessThan(tester.getRect(find.text('Elegir archivo')).top),
    );
  });

  testWidgets('cada expectativa se anuncia como texto legible', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, size: const Size(1360, 900));
    for (final fragment in const <String>[
      'PDF del banco',
      'Imagen o captura',
      'Foto con la cámara',
    ]) {
      // `RegExp` y no cadena exacta: los nodos de una tarjeta se fusionan, así
      // que el título viaja dentro de una etiqueta más larga.
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(fragment))),
        findsWidgets,
        reason: fragment,
      );
    }
    handle.dispose();
  });
}
