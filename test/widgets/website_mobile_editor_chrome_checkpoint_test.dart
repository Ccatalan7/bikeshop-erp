import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_block_sheet.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_contextual_dock.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_draft_recovery_host.dart';
import 'package:vinabike_erp/public_store/widgets/persistent_editor_shell.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

/// iPad checkpoint: the editor's top band, and the header as a real identity.
///
/// Every defect guarded here was read off a physical iPad frame at 451 logical
/// px (Split View, `/tienda?edit=true`) and traced to source, not inferred.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` — turn **t10** frame **10e** and
/// turn **t11** frame **11a**, both of which draw the phone as a
/// `safearea_top: 44` band of `--shell` followed by a `topbar: 48` band of
/// `--shell`, with a single identity label in the bar.
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
  ];

  WebsiteEditModeProvider newProvider() => WebsiteEditModeProvider()
    ..enterEditMode(blocks, const <String, dynamic>{}, pageId: 'page-a');

  /// A settings owner that never reaches the network.
  WebsiteService offlineService() => WebsiteService(
        supabase: SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode(<Object?>[]),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
        ),
        tenantService: TenantService.testing(
          currentUserId: () => 'user-a',
          profileLookup: (_) async => const [],
        ),
      );

  void useViewport(
    WidgetTester tester, {
    double width = 451,
    double height = 896,
    double topInset = 0,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.padding = FakeViewPadding(top: topInset);
    tester.view.viewPadding = FakeViewPadding(top: topInset);
    addTearDown(tester.view.reset);
  }

  Widget dockHost({
    required WebsiteEditModeProvider provider,
    double width = 451,
  }) {
    // The providers sit ABOVE `MaterialApp`, which is where `main.dart` puts
    // them: the `O-05` sheet is a route on the root navigator, so a provider
    // mounted under `home` would be invisible to the sheet body exactly as it
    // is not in production.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<WebsiteEditModeProvider>.value(value: provider),
        // The header controls read settings from this owner; the sheet body is
        // the real `_EditBlockTab`, so the harness has to supply it.
        ChangeNotifierProvider<WebsiteService>.value(value: offlineService()),
      ],
      child: MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: Brightness.light,
        ),
        home: WebsiteEditorChromeScope(
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

  group('la banda superior tiene un solo dueño y una sola aritmética', () {
    test('el alto total es el inset del sistema más la barra publicada', () {
      // The three literal `48`s that used to size the bar slot, the content
      // anchor and the overlay agreed only while the inset was zero.
      expect(WebsiteEditorChromeGeometry.topBarHeight, 48);
      expect(WebsiteEditorChromeGeometry.topBandHeightFor(0), 48);
      expect(
        WebsiteEditorChromeGeometry.topBandHeightFor(
          WebsiteEditorChromeGeometry.publishedPhoneSafeAreaTop,
        ),
        92,
      );
      // t10 10e / t11 11a publish the two bands separately; the bar constant
      // must never absorb the inset.
      expect(WebsiteEditorChromeGeometry.publishedPhoneSafeAreaTop, 44);
    });

    test('un inset real nunca se descuenta de la fila', () {
      for (final inset in <double>[0, 20, 44, 59]) {
        expect(
          WebsiteEditorChromeGeometry.topBandHeightFor(inset) -
              WebsiteEditorChromeGeometry.topBarHeight,
          inset,
          reason: 'la fila conserva sus 48 bajo un inset de $inset',
        );
      }
    });
  });

  group('la banda superior es una sola, y ningún hermano la invade', () {
    /// The real shell, with a real inset. Arithmetic alone could not have
    /// caught this: the shell's own siblings were positioned against a
    /// constant while the storefront reserved a runtime band.
    Widget shellHost({
      required WebsiteEditModeProvider provider,
      double workspaceTopInset = 0,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<WebsiteEditModeProvider>.value(
            value: provider,
          ),
          ChangeNotifierProvider<WebsiteService>.value(value: offlineService()),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: WorkspaceShellScope(
              topInset: workspaceTopInset,
              child: const PersistentEditorShell(
                child: ColoredBox(
                  key: ValueKey('shell-canvas'),
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }

    /// The shell kicks off a deferred editor-library load. Bounded pumps drain
    /// that timer so teardown does not fail on a timer the test never asked
    /// for — `pumpAndSettle` is wrong here, the saving state renders a
    /// progress indicator that never settles by design.
    Future<void> drainShell(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 60));
    }

    double publishedBand(WidgetTester tester) {
      final context =
          tester.element(find.byKey(const ValueKey('shell-canvas')));
      return WebsiteEditorChromeScope.maybeOf(context)!.topBandHeight;
    }

    /// The pane no longer overflows, so nothing is consumed: any exception is
    /// a real failure. `InspectorTabBar` replaced the five-`Expanded` row that
    /// used to overflow here for reasons unrelated to the top band.
    void consumePanePaletteOverflow(WidgetTester tester) {
      expect(tester.takeException(), isNull);
    }

    testWidgets(
        'sin barra de workspace, la banda es inset + 48 y el pane '
        'empieza ahí', (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      addTearDown(provider.dispose);
      // Ancho de pane (>=1050) con inset real: el caso que el iPad expone.
      useViewport(tester, width: 1200, height: 900, topInset: 44);
      await tester.pumpWidget(shellHost(provider: provider));
      await drainShell(tester);

      expect(publishedBand(tester), 92);

      // El aviso de borrador es el hermano que se posicionaba en 56 fijo: con
      // inset real invadía la banda y quedaba bajo el status bar. Ahora sale
      // de la banda publicada, igual que el pane.
      final recovery = find.byType(WebsiteEditorDraftRecoveryHost);
      expect(tester.getTopLeft(recovery).dy, greaterThanOrEqualTo(92));
      consumePanePaletteOverflow(tester);
    });

    testWidgets('bajo la barra de workspace el inset NO se reserva dos veces',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      addTearDown(provider.dispose);
      useViewport(tester, width: 1200, height: 900, topInset: 44);
      await tester.pumpWidget(
        shellHost(
          provider: provider,
          workspaceTopInset: WorkspaceShellScope.workspaceBarHeight,
        ),
      );
      await drainShell(tester);

      // La barra del ERP ya cubrió el área de status y el shell ya bajó el
      // editor por debajo de ella. Volver a reservar 44 aquí abriría un hueco
      // bajo una barra que ya está despejada.
      expect(
        publishedBand(tester),
        WebsiteEditorChromeGeometry.topBarHeight,
      );
      consumePanePaletteOverflow(tester);
    });

    testWidgets('el host contextual con inset tampoco desborda',
        (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      addTearDown(provider.dispose);
      useViewport(tester, width: 451, height: 896, topInset: 44);
      await tester.pumpWidget(shellHost(provider: provider));
      await drainShell(tester);

      expect(publishedBand(tester), 92);
      expect(tester.takeException(), isNull);
    });
  });

  group('el Encabezado es una identidad editable, no un bloque', () {
    testWidgets('seleccionarlo monta el dock con su nombre y su Editar',
        (tester) async {
      final provider = newProvider()
        ..selectBlock(WebsiteEditorChromeTarget.header.selectionId);
      useViewport(tester, topInset: 44);
      await tester.pumpWidget(dockHost(provider: provider));
      await tester.pump();

      // El dock existía sólo para ids que estuvieran en `blocks`; el
      // encabezado nunca lo está, así que en touch no había dock -> Editar ->
      // hoja para el header.
      expect(find.byKey(WebsiteEditorContextualDock.dockKey), findsOneWidget);
      expect(find.text('Encabezado'), findsOneWidget);
      expect(find.byKey(WebsiteEditorContextualDock.editKey), findsOneWidget);
    });

    testWidgets('las acciones que no le aplican quedan inertes y explicadas',
        (tester) async {
      final provider = newProvider()
        ..selectBlock(WebsiteEditorChromeTarget.header.selectionId);
      useViewport(tester);
      await tester.pumpWidget(dockHost(provider: provider));
      await tester.pump();

      // `A-01`: el límite se dice, no se esconde. Los controles conservan su
      // lugar y su 48 para que la fila no se reacomode bajo el dedo.
      for (final key in <Key>[
        WebsiteEditorContextualDock.moveUpKey,
        WebsiteEditorContextualDock.moveDownKey,
        WebsiteEditorContextualDock.visibilityKey,
        WebsiteEditorContextualDock.duplicateKey,
      ]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key sigue montado');
        final size = tester.getSize(find.byKey(key));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(
          tester.widget<IconButton>(find.byKey(key)).onPressed,
          isNull,
          reason: '$key no aplica al encabezado',
        );
        // Y dice por qué, en el mismo lugar donde `A-01` lo pide: el tooltip
        // del control inerte, que es también lo que anuncia el lector.
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(of: find.byKey(key), matching: find.byType(Tooltip)),
        );
        expect(tooltip.message, 'Encabezado es del sitio, no de esta página.');
      }
    });

    test('la selección de chrome no es una selección colgante', () {
      final provider = newProvider()
        ..selectBlock(WebsiteEditorChromeTarget.header.selectionId);
      addTearDown(provider.dispose);

      expect(
        provider.selectedChromeTarget,
        WebsiteEditorChromeTarget.header,
      );

      // Reordenar reconcilia las selecciones transitorias; el encabezado no
      // está en `blocks` y se perdía ahí — en escritorio también.
      provider.moveBlockDown('block-1');
      expect(
        provider.selectedBlockId,
        WebsiteEditorChromeTarget.header.selectionId,
      );

      provider.setMode(WebsiteEditorMode.preview);
      provider.setMode(WebsiteEditorMode.edit);
      expect(
        provider.selectedBlockId,
        WebsiteEditorChromeTarget.header.selectionId,
      );

      // Un id que sí es de bloque y ya no existe sigue resolviéndose a null.
      provider.selectBlock('block-borrado');
      provider.setMode(WebsiteEditorMode.preview);
      provider.setMode(WebsiteEditorMode.edit);
      expect(provider.selectedBlockId, isNull);
    });
  });

  group('el alcance que se muestra es el que la escritura honra', () {
    test('header y footer siempre escriben común', () {
      // Son settings del sitio: `updateHeaderSettings` no tiene ranura por
      // viewport, así que «Escribe en: móvil» sería una afirmación falsa por
      // más que el selector de viewport diga móvil.
      for (final chrome in WebsiteEditorChromeTarget.values) {
        for (final viewport in WebsiteViewport.values) {
          for (final scope in WebsiteWriteScope.values) {
            expect(
              WebsiteEditorContextualDock.scopeLabelForSelection(
                chrome: chrome,
                viewport: viewport,
                scope: scope,
              ),
              'Escribe en: común',
            );
          }
        }
      }
    });

    test('un bloque conserva la semántica responsive publicada', () {
      expect(
        WebsiteEditorContextualDock.scopeLabelForSelection(
          chrome: null,
          viewport: WebsiteViewport.mobile,
          scope: WebsiteWriteScope.viewport,
        ),
        'Escribe en: móvil',
      );
      expect(
        WebsiteEditorContextualDock.scopeLabelForSelection(
          chrome: null,
          viewport: WebsiteViewport.desktop,
          scope: WebsiteWriteScope.viewport,
        ),
        'Escribe en: común',
      );
    });
  });

  group('la hoja O-05 no ofrece navegación que no navega', () {
    testWidgets('el encabezado abre sin los tres tabs decorativos',
        (tester) async {
      final provider = newProvider()
        ..selectBlock(WebsiteEditorChromeTarget.header.selectionId);
      useViewport(tester);
      await tester.pumpWidget(dockHost(provider: provider));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(WebsiteBlockEditSheet.sheetKey), findsOneWidget);
      // `_EditBlockTab` devuelve los controles de chrome ANTES de mirar la
      // sección, así que tres tabs ahí cambiarían exactamente nada.
      expect(find.byKey(WebsiteBlockEditSheet.sectionTabsKey), findsNothing);
      expect(find.text('Encabezado'), findsWidgets);
    });

    testWidgets('un bloque sí los conserva', (tester) async {
      final provider = newProvider()..selectBlock('block-2');
      useViewport(tester);
      await tester.pumpWidget(dockHost(provider: provider));
      await tester.pump();

      await tester.tap(find.byKey(WebsiteEditorContextualDock.editKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(WebsiteBlockEditSheet.sectionTabsKey), findsOneWidget);
    });
  });
}
