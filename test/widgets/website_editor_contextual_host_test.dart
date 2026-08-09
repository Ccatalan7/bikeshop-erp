import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/block_action_bar.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_website_editor_panel.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_block_sheet.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_contextual_dock.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_host_theme.dart';
import 'package:vinabike_erp/shared/widgets/vb_sub_tabs.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Contextual authoring host — dock and `O-05` sheet.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames **10e** (390 light),
/// **10f** (sheet at the 60% cap), **10g** (keyboard), **10h** (390 dark) and
/// **10j** (tablet 834), plus `handoff-t10/spec.json`.
void main() {
  const blocks = <Map<String, dynamic>>[
    {
      'id': 'block-1',
      'block_type': 'hero',
      'block_data': <String, dynamic>{'title': 'Portada'},
      'is_visible': true,
      'sort_order': 0,
    },
    {
      'id': 'block-2',
      'block_type': 'about',
      'block_data': <String, dynamic>{'title': 'Nosotros'},
      'is_visible': true,
      'sort_order': 1,
    },
    {
      'id': 'block-3',
      'block_type': 'contact',
      'block_data': <String, dynamic>{'title': 'Contacto'},
      'is_visible': true,
      'sort_order': 2,
    },
  ];

  WebsiteEditModeProvider newProvider() => WebsiteEditModeProvider()
    ..enterEditMode(blocks, const <String, dynamic>{});

  /// The viewport is configured on the real test view, not faked in a
  /// descendant `MediaQuery`: a compact host must be proven under real
  /// constraints, otherwise a row that overflows at 390 still passes because
  /// it was laid out in the default 800×600 window.
  void useViewport(
    WidgetTester tester, {
    required double width,
    double height = 844,
    double bottomViewInset = 0,
    double bottomPadding = 20,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    tester.view.viewInsets = FakeViewPadding(bottom: bottomViewInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomPadding);
    // Flutter's `padding` is `viewPadding` minus `viewInsets`: with the
    // keyboard up the bottom safe area is already covered.
    tester.view.padding = FakeViewPadding(
      bottom: bottomViewInset > 0 ? 0 : bottomPadding,
    );
    addTearDown(tester.view.reset);
  }

  /// The declared cap of the mounted sheet, independent of its content height.
  double sheetCap(WidgetTester tester) {
    return tester
        .widget<ConstrainedBox>(
          find
              .ancestor(
                of: find.byKey(WebsiteBlockEditSheet.sheetKey),
                matching: find.byType(ConstrainedBox),
              )
              .first,
        )
        .constraints
        .maxHeight;
  }

  Widget host({
    required WebsiteEditModeProvider provider,
    required double width,
    Brightness brightness = Brightness.light,
  }) {
    final selectedBlockId = provider.selectedBlockId;
    if (selectedBlockId != null &&
        provider.renderedBlockViewportFor(selectedBlockId) == null) {
      provider.reportRenderedBlockViewport(
        selectedBlockId,
        WebsiteResponsiveDataCodec.viewportForDocumentWidth(
          provider.getBlockData(selectedBlockId),
          WebsiteEditorChromeGeometry.canvasWidthFor(width),
        ),
      );
    }
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: brightness,
      ),
      home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: WebsiteEditorChromeScope(
          editorWidth: width,
          canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(width),
          child: const Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: WebsiteEditorContextualDock(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  group('dock · sólo con selección, y a 48', () {
    testWidgets('sin bloque seleccionado no hay dock', (tester) async {
      final provider = newProvider();
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));

      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsNothing);
    });

    testWidgets('seleccionar un bloque monta el dock con su identidad',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsOneWidget);
      // La identidad se lee del registro, no de la clave serializada.
      expect(
        find.byKey(WebsiteEditorContextualDock.identityBadgeKey),
        findsOneWidget,
      );
      expect(find.text('block-2'), findsNothing);
      expect(find.text('about'), findsNothing);
    });

    testWidgets('390 claro: cada acción del dock mide al menos 48',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      for (final key in <Key>[
        WebsiteEditorContextualDock.moveUpKey,
        WebsiteEditorContextualDock.moveDownKey,
        WebsiteEditorContextualDock.visibilityKey,
        WebsiteEditorContextualDock.duplicateKey,
        WebsiteEditorContextualDock.overflowKey,
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(
          size.width,
          greaterThanOrEqualTo(WebsiteEditorContextualDock.touchTarget),
          reason: '$key mide ${size.width} de ancho',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(WebsiteEditorContextualDock.touchTarget),
          reason: '$key mide ${size.height} de alto',
        );
      }
      final edit =
          tester.getSize(find.byKey(WebsiteEditorContextualDock.editKey));
      expect(
        edit.height,
        greaterThanOrEqualTo(WebsiteEditorContextualDock.primaryActionHeight),
      );
    });

    testWidgets('390 oscuro monta la misma composición sin desbordar',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(
        host(provider: provider, width: 390, brightness: Brightness.dark),
      );
      await tester.pump();

      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      final dock = tester.getSize(
        find.byKey(WebsiteEditorContextualDock.dockKey),
      );
      expect(dock.width, lessThanOrEqualTo(390));
    });

    testWidgets(
        '834 usa el MISMO dock: tablet no recibe una tercera '
        'composición', (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 834, height: 640);
      await tester.pumpWidget(host(provider: provider, width: 834));
      await tester.pump();

      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el dock consume el inset inferior una sola vez',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390, bottomPadding: 34);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      final safeAreas = find.descendant(
        of: find.byKey(WebsiteEditorContextualDock.dockKey),
        matching: find.byType(SafeArea),
      );
      expect(safeAreas, findsOneWidget);
      expect(tester.widget<SafeArea>(safeAreas).bottom, isTrue);
    });
  });

  group('dock · comandos y límites', () {
    testWidgets('el primer bloque no puede subir y el último no puede bajar',
        (tester) async {
      final provider = newProvider()..selectBlock('block-1');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      IconButton buttonOf(Key key) =>
          tester.widget<IconButton>(find.byKey(key));

      expect(buttonOf(WebsiteEditorContextualDock.moveUpKey).onPressed, isNull);
      expect(
        buttonOf(WebsiteEditorContextualDock.moveDownKey).onPressed,
        isNotNull,
      );

      provider.selectBlock('block-3');
      await tester.pump();

      expect(
        buttonOf(WebsiteEditorContextualDock.moveUpKey).onPressed,
        isNotNull,
      );
      expect(
        buttonOf(WebsiteEditorContextualDock.moveDownKey).onPressed,
        isNull,
      );
    });

    testWidgets('mover abajo reordena una vez y conserva la selección',
        (tester) async {
      final provider = newProvider()..selectBlock('block-1');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.moveDownKey));
      await tester.pump();

      expect(
        provider.blocks.map((block) => block['id']).toList(),
        ['block-2', 'block-1', 'block-3'],
      );
      expect(provider.selectedBlockId, 'block-1');
    });

    testWidgets('visibilidad y duplicar usan los comandos del provider',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.visibilityKey));
      await tester.pump();
      expect(
        provider.blocks.firstWhere(
          (block) => block['id'] == 'block-2',
        )['is_visible'],
        isFalse,
      );

      await tester.tap(find.byKey(WebsiteEditorContextualDock.duplicateKey));
      await tester.pump();
      expect(provider.blocks.length, 4);
    });

    testWidgets('eliminar exige confirmación y la salida segura no borra',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.overflowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar bloque').last);
      await tester.pumpAndSettle();

      // La confirmación es una decisión, no un Sí/No.
      expect(find.text('¿Eliminar este bloque?'), findsOneWidget);
      expect(find.text('Sí'), findsNothing);
      expect(find.text('No'), findsNothing);

      await tester.tap(find.text('Conservar bloque'));
      await tester.pumpAndSettle();
      expect(provider.blocks.length, 3);

      await tester.tap(find.byKey(WebsiteEditorContextualDock.overflowKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar bloque').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar bloque').last);
      await tester.pumpAndSettle();

      expect(provider.blocks.length, 2);
    });

    testWidgets('deshacer/rehacer viven en el menú y explican su estado inerte',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.overflowKey));
      await tester.pumpAndSettle();

      expect(find.text('Deshacer'), findsOneWidget);
      expect(find.text('No hay cambios que deshacer.'), findsOneWidget);
      expect(find.text('Rehacer'), findsOneWidget);
      expect(find.text('No hay nada que rehacer.'), findsOneWidget);
    });
  });

  group('alcance de escritura visible', () {
    test('escritorio es la base, diga lo que diga el selector', () {
      expect(
        WebsiteEditorContextualDock.scopeLabelFor(
          viewport: WebsiteViewport.desktop,
          scope: WebsiteWriteScope.viewport,
        ),
        'Escribe en: común',
      );
    });

    test('móvil y tablet nombran su viewport', () {
      expect(
        WebsiteEditorContextualDock.scopeLabelFor(
          viewport: WebsiteViewport.mobile,
          scope: WebsiteWriteScope.viewport,
        ),
        'Escribe en: móvil',
      );
      expect(
        WebsiteEditorContextualDock.scopeLabelFor(
          viewport: WebsiteViewport.tablet,
          scope: WebsiteWriteScope.viewport,
        ),
        'Escribe en: tablet',
      );
      expect(
        WebsiteEditorContextualDock.scopeLabelFor(
          viewport: WebsiteViewport.mobile,
          scope: WebsiteWriteScope.shared,
        ),
        'Escribe en: común',
      );
    });
  });

  group('O-05 · la hoja contextual', () {
    testWidgets('el placeholder desktop nace sobre el mismo grafito',
        (tester) async {
      useViewport(tester, width: 1200);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: Brightness.light,
          ),
          home: ChangeNotifierProvider<WebsiteEditModeProvider>(
            create: (_) => newProvider(),
            child: const Scaffold(
              body: SizedBox(
                width: 420,
                child: DeferredWebsiteEditorPanel(),
              ),
            ),
          ),
        ),
      );

      final spinner = find.byType(CircularProgressIndicator);
      expect(spinner, findsOneWidget);
      expect(Theme.of(tester.element(spinner)).brightness, Brightness.dark);
      expect(
        tester
            .widgetList<Material>(find.ancestor(
              of: spinner,
              matching: find.byType(Material),
            ))
            .any((material) =>
                material.color == WebsiteEditorInspectorTheme.canvas),
        isTrue,
      );

      // Let the deferred-load timer finish after the visual assertion. Leaving
      // it pending would make this test, rather than the production widget,
      // own the next suite's load state.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    for (final hostBrightness in Brightness.values) {
      testWidgets(
          'el inspector completo permanece oscuro desde un ERP '
          '${hostBrightness.name}', (tester) async {
        final provider = newProvider()..selectBlock('block-2');
        useViewport(tester, width: 390);
        await tester.pumpWidget(
          host(
            provider: provider,
            width: 390,
            brightness: hostBrightness,
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
        await tester.pump();

        final sheet = find.byKey(WebsiteBlockEditSheet.sheetKey);
        expect(sheet, findsOneWidget);
        final sheetTheme = Theme.of(tester.element(sheet));
        expect(sheetTheme.brightness, Brightness.dark);
        expect(
          sheetTheme.colorScheme.surface,
          WebsiteEditorInspectorTheme.canvas,
        );
        expect(tester.widget<Material>(sheet).color,
            sheetTheme.colorScheme.surface);

        final tabs = find.byKey(WebsiteBlockEditSheet.sectionTabsKey);
        expect(Theme.of(tester.element(tabs)).brightness, Brightness.dark);
        expect(
          Theme.of(
            tester.element(find.byKey(WebsiteBlockEditSheet.doneKey)),
          ).brightness,
          Brightness.dark,
        );

        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(TextField), findsWidgets);
        expect(
          Theme.of(tester.element(find.byType(TextField).first)).brightness,
          Brightness.dark,
        );
        expect(tester.widget<Material>(sheet).color,
            sheetTheme.colorScheme.surface);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Editar abre la hoja y el lienzo sigue montado',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(WebsiteBlockEditSheet.sheetKey), findsOneWidget);
      expect(
        tester
            .widget<WebsiteContextualSheetScaffold>(
              find.byType(WebsiteContextualSheetScaffold),
            )
            .scope,
        isNull,
        reason: 'una hoja de bloque mezcla campos comunes y responsive',
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ResponsiveFieldAttribution,
        ),
        findsWidgets,
      );
      expect(find.text('Siempre común'), findsWidgets);
      // El dock — y con él el host del lienzo — nunca se desmonta.
      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsOneWidget);
      // Y lo que se monta dentro son los controles REALES del inspector, no
      // una superficie compacta paralela: el mismo `_EditBlockTab` del pane.
      expect(find.text('Título'), findsWidgets);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('la hoja no supera el 60% del alto disponible', (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final size = tester.getSize(find.byKey(WebsiteBlockEditSheet.sheetKey));
      expect(
        size.height,
        lessThanOrEqualTo(
          WebsiteBlockEditSheetGeometry.maxHeightFor(844) + 0.5,
        ),
      );
      // El tope se aplica aunque el contenido sea corto: es una restricción
      // declarada, no una consecuencia del contenido de este bloque.
      expect(
        sheetCap(tester),
        closeTo(WebsiteBlockEditSheetGeometry.maxHeightFor(844), 0.5),
      );
    });

    testWidgets(
        'con el teclado abierto la hoja se mide contra el alto que '
        'queda y no desborda', (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390, bottomViewInset: 292);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        sheetCap(tester),
        closeTo(WebsiteBlockEditSheetGeometry.maxHeightFor(844 - 292), 0.5),
      );
      final size = tester.getSize(find.byKey(WebsiteBlockEditSheet.sheetKey));
      expect(
        size.height,
        lessThanOrEqualTo(
          WebsiteBlockEditSheetGeometry.maxHeightFor(844 - 292) + 0.5,
        ),
      );
      // Y el teclado empuja la hoja: el CTA nunca queda detrás de él.
      final done = tester.getRect(find.byKey(WebsiteBlockEditSheet.doneKey));
      expect(done.bottom, lessThanOrEqualTo(844 - 292));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'abrir y cerrar no escribe, no crea historia y conserva la '
        'selección, el viewport y el alcance', (tester) async {
      final provider = newProvider()
        ..selectBlock('block-2')
        ..setDevicePreviewMode(DevicePreviewMode.mobile)
        ..setWriteScope(WebsiteWriteScope.viewport);
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      final blocksBefore = provider.blocks;
      final dirtyBefore = provider.hasUnsavedChanges;
      final canUndoBefore = provider.canUndo;

      await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(WebsiteBlockEditSheet.doneKey));
      await tester.pumpAndSettle();

      expect(find.byKey(WebsiteBlockEditSheet.sheetKey), findsNothing);
      expect(provider.selectedBlockId, 'block-2');
      expect(provider.devicePreviewMode, DevicePreviewMode.mobile);
      expect(provider.writeScope, WebsiteWriteScope.viewport);
      expect(provider.hasUnsavedChanges, dirtyBefore);
      expect(provider.canUndo, canUndoBefore);
      expect(provider.blocks, blocksBefore);
    });

    testWidgets('la hoja NO tiene un segundo Guardar', (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Guardar'), findsNothing);
      expect(find.text('Descartar'), findsNothing);
      expect(find.text('Copias de seguridad'), findsNothing);
    });

    testWidgets('T-04: las tres secciones se anuncian y se pueden cambiar',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      for (final section in WebsiteBlockEditSection.values) {
        expect(
          find.byKey(VbSubTabs.tabKey(section)),
          findsOneWidget,
          reason: 'falta la sección ${section.label}',
        );
        final size = tester.getSize(
          find.byKey(VbSubTabs.tabKey(section)),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(WebsiteEditorContextualDock.touchTarget),
        );
      }

      await tester.tap(
        find.byKey(VbSubTabs.tabKey(WebsiteBlockEditSection.style)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('la geometría de O-05 sale de Design', () {
    test('anatomía publicada en handoff-t10', () {
      expect(WebsiteBlockEditSheetGeometry.topRadius, 14);
      expect(WebsiteBlockEditSheetGeometry.handleWidth, 34);
      expect(WebsiteBlockEditSheetGeometry.handleHeight, 4);
      expect(WebsiteBlockEditSheetGeometry.titleSize, 14);
      expect(WebsiteBlockEditSheetGeometry.ctaHeight, 50);
      expect(WebsiteBlockEditSheetGeometry.maxHeightFraction, 0.60);
      expect(
          WebsiteBlockEditSheetGeometry.maxHeightFor(844), closeTo(506.4, 1));
    });
  });

  group('el chrome contextual existe sólo en Edit', () {
    testWidgets('Vista previa no muestra dock aunque haya selección',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();
      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsOneWidget);

      provider.setMode(WebsiteEditorMode.preview);
      await tester.pump();
      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsNothing);

      provider.setMode(WebsiteEditorMode.public);
      await tester.pump();
      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsNothing);
    });

    testWidgets('volver de Vista previa devuelve el dock del mismo bloque',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 430, height: 896);
      await tester.pumpWidget(host(provider: provider, width: 430));
      await tester.pump();
      final identity = WebsiteEditorContextualDock.identityLabelFor(
        provider.getBlock('block-2')!,
      );
      expect(find.text(identity), findsOneWidget);

      provider.setMode(WebsiteEditorMode.preview);
      await tester.pump();
      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsNothing);

      provider.setMode(WebsiteEditorMode.edit);
      await tester.pump();

      // El operador vuelve a lo que estaba haciendo: mismo bloque, mismo dock.
      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsOneWidget);
      expect(find.text(identity), findsOneWidget);
      expect(provider.selectedBlockId, 'block-2');
    });

    testWidgets('un workspace de gestión tampoco lo muestra', (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      provider.openWorkspace(WebsiteWorkspaceMode.settings);
      await tester.pump();
      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsNothing);
    });
  });

  group('la barra flotante de bloque es chrome de puntero', () {
    testWidgets('la composición contextual no la pinta', (tester) async {
      // El dock ya lleva identidad, reorden, duplicar, visibilidad y eliminar a
      // 48. Repetirlas en una barra flotante de 18 sería un segundo owner y un
      // target por debajo del mínimo.
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester, width: 390);
      await tester.pumpWidget(host(provider: provider, width: 390));
      await tester.pump();

      expect(find.byType(BlockActionBar), findsNothing);
    });
  });
}
