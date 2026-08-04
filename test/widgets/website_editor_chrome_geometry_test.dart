import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/shared/widgets/vb_segmented.dart';

/// Geometry owner contract.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 (10a, 10b, 10j, 10k) +
/// `handoff-t10/spec.json` `derived_rules`.
void main() {
  group('la geometría sale de Design, no de una constante local', () {
    test('el pane usa el mínimo publicado por O-04', () {
      expect(WebsiteEditorChromeGeometry.inspectorWidth, 420);
      expect(WebsiteEditorChromeGeometry.inspectorMaxWidthFraction, 0.40);
      expect(WebsiteEditorChromeGeometry.minimumCanvasWidth, 560);
      expect(WebsiteEditorChromeGeometry.topBarHeight, 48);
      expect(WebsiteEditorChromeGeometry.mobileFrameWidth, 390);
      expect(WebsiteEditorChromeGeometry.tabletFrameWidth, 820);
    });

    test('1050 es derivado: manda la restricción mayor de O-04 y T-05', () {
      const fromSideSheet = WebsiteEditorChromeGeometry.inspectorWidth /
          WebsiteEditorChromeGeometry.inspectorMaxWidthFraction;
      const fromSplitPane = WebsiteEditorChromeGeometry.minimumCanvasWidth +
          WebsiteEditorChromeGeometry.inspectorWidth;
      expect(fromSideSheet, 1050);
      expect(fromSplitPane, 980);
      expect(
        WebsiteEditorChromeGeometry.paneMinimumEditorWidth,
        fromSideSheet,
        reason: 'manda la mayor de las dos restricciones publicadas',
      );
    });

    test('el 380 heredado ya no es una geometría válida', () {
      expect(WebsiteEditorChromeGeometry.inspectorWidth, isNot(380));
      expect(WebsiteEditorChromeGeometry.paneWidthFor(1440), 420);
    });
  });

  group('composición por ancho del editor', () {
    test('pane sólo desde 1050', () {
      expect(
        WebsiteEditorChromeGeometry.compositionFor(1050),
        WebsiteEditorChromeComposition.pane,
      );
      expect(
        WebsiteEditorChromeGeometry.compositionFor(1049),
        WebsiteEditorChromeComposition.contextual,
      );
    });

    test('tablet 820 nunca recibe un pane: usa la composición contextual', () {
      expect(
        WebsiteEditorChromeGeometry.compositionFor(820),
        WebsiteEditorChromeComposition.contextual,
      );
      expect(WebsiteEditorChromeGeometry.paneWidthFor(820), isNull);
    });

    test('teléfono 390 tampoco: jamás un panel lateral comprimido', () {
      expect(
        WebsiteEditorChromeGeometry.compositionFor(390),
        WebsiteEditorChromeComposition.contextual,
      );
      expect(WebsiteEditorChromeGeometry.paneWidthFor(390), isNull);
    });

    test('el lienzo nunca baja del mínimo de T-05 cuando hay pane', () {
      for (final width in <double>[1050, 1200, 1440, 1920]) {
        final canvas = WebsiteEditorChromeGeometry.canvasWidthFor(width);
        expect(
          canvas,
          greaterThanOrEqualTo(
            WebsiteEditorChromeGeometry.minimumCanvasWidth,
          ),
          reason: 'a $width el lienzo queda en $canvas',
        );
      }
    });

    test('sin pane el lienzo se queda con todo el ancho', () {
      expect(WebsiteEditorChromeGeometry.canvasWidthFor(390), 390);
      expect(WebsiteEditorChromeGeometry.canvasWidthFor(820), 820);
    });
  });

  group('la clase de viewport sale del lienzo, no de la ventana', () {
    test('usa el owner canónico 600/900', () {
      expect(
        WebsiteEditorChromeGeometry.viewportForCanvasWidth(390),
        WebsiteViewport.mobile,
      );
      expect(
        WebsiteEditorChromeGeometry.viewportForCanvasWidth(599),
        WebsiteViewport.mobile,
      );
      expect(
        WebsiteEditorChromeGeometry.viewportForCanvasWidth(600),
        WebsiteViewport.tablet,
      );
      expect(
        WebsiteEditorChromeGeometry.viewportForCanvasWidth(899),
        WebsiteViewport.tablet,
      );
      expect(
        WebsiteEditorChromeGeometry.viewportForCanvasWidth(900),
        WebsiteViewport.desktop,
      );
    });

    test(
      'una ventana de escritorio con pane abierto puede dar un lienzo tablet',
      () {
        // 1131 lógicos de slot (rail + panel global del ERP ya descontados)
        // menos el pane de 420 deja 711: el bloque debe renderizar como tablet
        // aunque la ventana mida 1631.
        const editorWidth = 1131.0;
        final canvas = WebsiteEditorChromeGeometry.canvasWidthFor(editorWidth);
        expect(canvas, 711);
        expect(
          WebsiteEditorChromeGeometry.viewportForCanvasWidth(canvas),
          WebsiteViewport.tablet,
        );
      },
    );

    test('el marco de dispositivo usa los anchos de t10', () {
      expect(
        WebsiteEditorChromeGeometry.frameWidthFor(
          WebsiteViewport.mobile,
          availableWidth: 1440,
        ),
        390,
      );
      expect(
        WebsiteEditorChromeGeometry.frameWidthFor(
          WebsiteViewport.tablet,
          availableWidth: 1440,
        ),
        820,
      );
      expect(
        WebsiteEditorChromeGeometry.frameWidthFor(
          WebsiteViewport.desktop,
          availableWidth: 1440,
        ),
        1440,
      );
    });

    test('un host de teléfono nunca desborda el marco canónico de 390', () {
      expect(
        WebsiteEditorChromeGeometry.frameWidthFor(
          WebsiteViewport.mobile,
          availableWidth: 358,
        ),
        358,
      );
      expect(
        WebsiteEditorChromeGeometry.frameWidthFor(
          WebsiteViewport.tablet,
          availableWidth: 390,
        ),
        390,
      );
    });
  });

  group('densidad y host', () {
    test('F-06 fuerza touch bajo 900 lógicos', () {
      expect(WebsiteEditorChromeGeometry.densityFor(899), VbDensity.touch);
      expect(WebsiteEditorChromeGeometry.densityFor(900), VbDensity.compact);
      expect(WebsiteEditorChromeGeometry.densityFor(390), VbDensity.touch);
    });

    test('un puntero estrecho sigue siendo puntero; sólo <600 es teléfono', () {
      expect(
        WebsiteEditorChromeGeometry.hostClassFor(599),
        WebsiteAuthoringHostClass.phone,
      );
      expect(
        WebsiteEditorChromeGeometry.hostClassFor(600),
        WebsiteAuthoringHostClass.desktop,
      );
      expect(
        WebsiteEditorChromeGeometry.hostClassFor(820),
        WebsiteAuthoringHostClass.desktop,
      );
    });
  });

  group('los cuatro consumidores leen una sola geometría', () {
    const owners = <String>[
      'lib/public_store/widgets/persistent_editor_shell.dart',
      'lib/public_store/widgets/public_store_layout.dart',
      'lib/modules/website/widgets/website_editor_panel.dart',
      'lib/modules/website/widgets/deferred_website_editor_panel.dart',
    ];

    test('ninguno conserva una decisión propia de 380', () {
      for (final path in owners) {
        final source = File(path).readAsStringSync();
        // Se permite nombrarlo en un comentario que explica por qué murió;
        // lo que no puede quedar es un 380 en código.
        final code = source
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .where((line) => !line.trimLeft().startsWith('///'))
            .join('\n');
        expect(
          code.contains('380'),
          isFalse,
          reason: '$path todavía decide un ancho por su cuenta',
        );
      }
    });

    test('ninguno declara su propio ancho de panel', () {
      for (final path in owners) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('_editorPanelWidth') ||
              source.contains('_externalEditorPanelWidth'),
          isFalse,
          reason: '$path conserva una constante de ancho local',
        );
      }
    });

    test('los que pintan el panel consumen el scope', () {
      for (final path in <String>[
        'lib/modules/website/widgets/website_editor_panel.dart',
        'lib/modules/website/widgets/deferred_website_editor_panel.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('WebsiteEditorChromeScope.maybeOf'),
          isTrue,
          reason: '$path debe leer el owner publicado',
        );
      }
    });

    test('el shell publica el scope y no lo inserta condicionalmente', () {
      final source = File(owners.first).readAsStringSync();
      expect(source.contains('WebsiteEditorChromeScope('), isTrue);
      // El scope se monta siempre; sólo el panel es un hermano opcional.
      expect(
        source.contains('if (mountsPane)'),
        isTrue,
        reason: 'la condición vive en el hermano, no en el scope',
      );
    });
  });

  group('el scope publica una sola verdad al subárbol', () {
    testWidgets('escritorio 1440 expone pane y lienzo desktop', (tester) async {
      late WebsiteEditorChromeScope scope;
      await tester.pumpWidget(
        MaterialApp(
          home: WebsiteEditorChromeScope(
            editorWidth: 1440,
            canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(1440),
            child: Builder(
              builder: (context) {
                scope = WebsiteEditorChromeScope.maybeOf(context)!;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(scope.usesPane, isTrue);
      expect(scope.paneWidth, 420);
      expect(scope.canvasViewport, WebsiteViewport.desktop);
    });

    testWidgets('teléfono 390 expone composición contextual', (tester) async {
      late WebsiteEditorChromeScope scope;
      await tester.pumpWidget(
        MaterialApp(
          home: WebsiteEditorChromeScope(
            editorWidth: 390,
            canvasWidth: 390,
            child: Builder(
              builder: (context) {
                scope = WebsiteEditorChromeScope.maybeOf(context)!;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(scope.usesPane, isFalse);
      expect(scope.paneWidth, isNull);
      expect(
        scope.composition,
        WebsiteEditorChromeComposition.contextual,
      );
      expect(scope.canvasViewport, WebsiteViewport.mobile);
      expect(scope.hostClass, WebsiteAuthoringHostClass.phone);
      expect(scope.density, VbDensity.touch);
    });

    testWidgets('cruzar 899→900→899 sólo cambia propiedades, no el subárbol',
        (tester) async {
      final probeKey = GlobalKey();
      final states = <WebsiteViewport>[];

      Widget build(double width) {
        return MaterialApp(
          home: WebsiteEditorChromeScope(
            editorWidth: width,
            canvasWidth: width,
            child: Builder(
              key: probeKey,
              builder: (context) {
                states.add(
                  WebsiteEditorChromeScope.maybeOf(context)!.canvasViewport,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      }

      await tester.pumpWidget(build(899));
      final element = probeKey.currentContext;
      await tester.pumpWidget(build(900));
      await tester.pumpWidget(build(899));

      expect(states, [
        WebsiteViewport.tablet,
        WebsiteViewport.desktop,
        WebsiteViewport.tablet,
      ]);
      expect(
        identical(probeKey.currentContext, element),
        isTrue,
        reason: 'el mismo Element sobrevive al cruce del breakpoint',
      );
    });
  });
}
