import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_command_scope.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/customer_account_service.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_segmented.dart';
import 'package:vinabike_erp/shared/widgets/window_chrome_layout_region_scope.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

/// The editor command bar, in both compositions.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames **10e/10f/10h** (390) and
/// **10j** (834). The dense bar at 1440 is the regression canary: the compact
/// composition is a replacement, never a change to the pane host.
class _GrantingWebsiteService extends WebsiteService {
  static const _lease = WebsiteEditorCapabilitySnapshot(
    identity: 'test-user',
    activeTenantId: 'test-tenant',
    storefrontTenantId: 'test-tenant',
    hasAuthority: true,
  );

  /// Every tenant-explicit settings statement this service received, in order.
  /// The publication regression reads it to prove there is exactly ONE guarded
  /// statement owned by the layout.
  final List<({String tenantId, Map<String, String> settings})>
      settingStatements = <({String tenantId, Map<String, String> settings})>[];

  @override
  WebsiteEditorCapabilitySnapshot? editorCapabilitySync(
    String? storefrontTenantId,
  ) =>
      _lease;

  @override
  Future<WebsiteEditorCapabilitySnapshot> resolveEditorCapability(
    String? storefrontTenantId,
  ) async =>
      _lease;

  @override
  Future<void> saveSettingsForTenant(
    String tenantId,
    Map<String, String> settings, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    writeGuard?.call();
    settingStatements.add((
      tenantId: tenantId,
      settings: Map<String, String>.unmodifiable(settings),
    ));
    writeGuard?.call();
  }
}

/// Registers the typeface the editor bar actually renders with.
///
/// `WebsiteThemeBuilder` applies `WebsiteFontRegistry.bodyDefault` — Barlow —
/// to the storefront theme the bar is built inside, and Barlow ships in this
/// repository's `pubspec.yaml` assets. Without this the harness measures the
/// test placeholder font, whose glyphs are far wider than Barlow's, so a bar
/// that fits in the product overflows here and an overflow assertion becomes
/// meaningless in both directions.
///
/// `FontLoader` is not weight-aware, so the whole family is registered from the
/// weights the bar uses; the measured advance widths are Barlow's.
Future<void> _loadEditorBarFont() async {
  final loader = FontLoader('Barlow');
  for (final asset in const <String>[
    'assets/fonts/Barlow-Regular.ttf',
    'assets/fonts/Barlow-Medium.ttf',
    'assets/fonts/Barlow-SemiBold.ttf',
  ]) {
    loader.addFont(rootBundle.load(asset));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadEditorBarFont();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  late int saveCalls;
  late int discardCalls;

  /// The service the mounted layout uses, so a test can inspect the persisted
  /// writes it actually received.
  late _GrantingWebsiteService website;

  setUp(() {
    saveCalls = 0;
    discardCalls = 0;
  });

  Future<WebsiteEditModeProvider> pumpEditor(
    WidgetTester tester, {
    required double width,
    double height = 844,
    bool isSaving = false,
    bool dirty = true,
    Brightness brightness = Brightness.light,
    double topInset = 0,
    double leftInset = 0,
    double rightInset = 0,
    EdgeInsets adaptedMargins = EdgeInsets.zero,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    tester.view.viewPadding = FakeViewPadding(
      top: topInset,
      left: leftInset,
      right: rightInset,
    );
    tester.view.padding = FakeViewPadding(
      top: topInset,
      left: leftInset,
      right: rightInset,
    );
    addTearDown(tester.view.reset);

    PublicStoreRuntimeConfig.isErpMounted = true;
    addTearDown(() => PublicStoreRuntimeConfig.isErpMounted = false);

    final editMode = WebsiteEditModeProvider()
      ..enterEditMode(
        const [
          {
            'id': 'block-1',
            'block_type': 'hero',
            'block_data': <String, dynamic>{'title': 'Portada'},
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
      );
    if (dirty) {
      editMode.updateBlockData('block-1', 'title', 'Portada editada');
    }

    website = _GrantingWebsiteService();
    final tenant = PublicStoreTenantProvider(TenantDetectionService());
    final cart = CartProvider();
    final inventory = PublicInventoryService();
    final scrollState = PublicStoreScrollState();
    final account = CustomerAccountService();

    final router = GoRouter(
      initialLocation: '/tienda',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: editMode),
                ChangeNotifierProvider<WebsiteService>.value(value: website),
                ChangeNotifierProvider.value(value: tenant),
                ChangeNotifierProvider.value(value: cart),
                ChangeNotifierProvider.value(value: inventory),
                Provider.value(value: scrollState),
                ChangeNotifierProvider.value(value: account),
              ],
              // The two scopes the shell publishes in production, supplied
              // directly: this test is about the bar's composition and its
              // single save owner, not about the shell's tenant plumbing.
              child: WindowChromeLayoutRegionScope(
                margins: adaptedMargins,
                child: WebsiteEditorCommandScope(
                  isSaving: isSaving,
                  onSave: () async => saveCalls++,
                  onDiscard: () => discardCalls++,
                  onRestoreComplete: () async {},
                  child: WebsiteEditorChromeScope(
                    editorWidth: width,
                    canvasWidth:
                        WebsiteEditorChromeGeometry.canvasWidthFor(width),
                    topBandHeight:
                        WebsiteEditorChromeGeometry.topBandHeightFor(topInset),
                    child: PublicStoreLayout(child: navigationShell),
                  ),
                ),
              ),
            );
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/tienda',
                  builder: (context, state) => const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        // The REAL ERP theme, not a bare `ThemeData`. The bar's shared
        // segmented controls mount only when the host publishes
        // `VinabikeThemeRoles`; with a plain theme they resolved to
        // `SizedBox.shrink()`, so the dense-bar canary was measuring a bar
        // that had neither the viewport nor the write-scope control in it.
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: brightness,
        ),
      ),
    );
    await tester.pump();
    // The layout kicks off a deferred ERP library load; drain that timer so
    // teardown does not fail on a timer the test never asked for. Bounded
    // pumps, not `pumpAndSettle`: the saving state renders a progress
    // indicator that never settles by design.
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(milliseconds: 50));
    return editMode;
  }

  group('390 · la barra compacta no comprime la densa', () {
    testWidgets(
        'mantiene cerrar, identidad, viewport, deshacer, Guardar y '
        'un desborde', (tester) async {
      await pumpEditor(tester, width: 390);

      expect(
          find.byKey(const ValueKey('editor-compact-close')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-compact-undo')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-compact-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('editor-compact-more')), findsOneWidget);
      // Identidad visible, UNA línea. t10 10e y t11 11a ponen una sola
      // etiqueta ahí; la segunda línea acento que había antes agregaba un
      // tercer peso compitiendo justo donde menos ancho hay, y a 390 se comía
      // el espacio de la identidad real.
      final identity = find.descendant(
        of: find.byKey(const ValueKey('editor-compact-bar-identity')),
        matching: find.byType(Text),
      );
      expect(identity, findsOneWidget);
      expect(tester.widget<Text>(identity).maxLines, 1);
      expect(find.textContaining('· 390'), findsNothing);

      // Pero el viewport NO se pierde: sigue anunciado por el owner real de
      // la identidad, que es lo que lee un lector de pantalla.
      final semantics = tester.getSemantics(
        find.byKey(const ValueKey('editor-compact-bar-identity')),
      );
      expect(semantics.label, contains('escritorio'));
      expect(semantics.label, contains('Editando'));
      // Y la barra densa NO está comprimida dentro.
      expect(find.text('Catálogo web'), findsNothing);
      expect(find.text('Publicado'), findsNothing);
      expect(find.text('Estructura'), findsNothing);
    });

    testWidgets('sin desbordes de Row a 390 en claro y en oscuro',
        (tester) async {
      for (final brightness in Brightness.values) {
        await pumpEditor(tester, width: 390, brightness: brightness);
        expect(
          tester.takeException(),
          isNull,
          reason: 'la barra desborda en $brightness',
        );
      }
    });

    testWidgets('los controles de la barra cumplen 48', (tester) async {
      await pumpEditor(tester, width: 390);

      for (final key in const <ValueKey<String>>[
        ValueKey('editor-compact-close'),
        ValueKey('editor-compact-undo'),
        ValueKey('editor-compact-more'),
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(48), reason: '$key');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$key');
      }

      // `Guardar` se pinta a 36 dentro de la barra de 48 (t10 10e) y expande
      // su área de toque a 48 con `padded` — el patrón `A-02`.
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('editor-compact-save')),
      );
      expect(
        save.style?.tapTargetSize,
        MaterialTapTargetSize.padded,
      );
    });

    testWidgets('la barra mide exactamente la altura publicada',
        (tester) async {
      await pumpEditor(tester, width: 390);
      final systemCanvas = find.ancestor(
        of: find.byKey(const ValueKey('editor-compact-close')),
        matching: find.byType(WorkspaceSystemUiCanvas),
      );

      expect(systemCanvas, findsOneWidget);
      final bar = tester.getSize(systemCanvas);
      expect(bar.height, WebsiteEditorChromeGeometry.topBarHeight);

      // The painted status-bar surface and its icon brightness are one owner.
      // A feature-local Container could keep the height green while silently
      // inheriting stale system icons, which is the physical iPad regression
      // this contract protects.
      expect(
        find.descendant(
          of: systemCanvas,
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
        findsOneWidget,
      );
    });

    testWidgets('el inset físico ocupa una banda propia exactamente una vez',
        (tester) async {
      const inset = WebsiteEditorChromeGeometry.publishedPhoneSafeAreaTop;
      final totalBand = WebsiteEditorChromeGeometry.topBandHeightFor(inset);
      await pumpEditor(tester, width: 390, topInset: inset);

      final systemCanvas = find.ancestor(
        of: find.byKey(const ValueKey('editor-compact-close')),
        matching: find.byType(WorkspaceSystemUiCanvas),
      );
      expect(tester.getRect(systemCanvas), Rect.fromLTWH(0, 0, 390, totalBand));
      expect(
        tester.getRect(find.byKey(const ValueKey('editor-compact-close'))).top,
        inset,
      );
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey('storefront_content_viewport')),
            )
            .top,
        totalBand,
      );
    });

    testWidgets('la fila evita los insets laterales sin estrechar el canvas',
        (tester) async {
      const leftInset = 80.0;
      const rightInset = 24.0;
      await pumpEditor(
        tester,
        width: 390,
        leftInset: leftInset,
        rightInset: rightInset,
      );

      expect(
        tester.getRect(find.byKey(const ValueKey('editor-compact-close'))).left,
        greaterThanOrEqualTo(leftInset),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('editor-compact-more'))).right,
        lessThanOrEqualTo(390 - rightInset),
      );
      expect(
        tester.getRect(
          find.byKey(const ValueKey('storefront_content_viewport')),
        ),
        const Rect.fromLTWH(
          0,
          WebsiteEditorChromeGeometry.topBarHeight,
          390,
          844 - WebsiteEditorChromeGeometry.topBarHeight,
        ),
      );
    });

    testWidgets(
        'la fila consume la región adaptativa aunque SafeArea diga cero',
        (tester) async {
      const adapted = EdgeInsets.only(left: 80, right: 24);
      await pumpEditor(
        tester,
        width: 390,
        adaptedMargins: adapted,
      );

      expect(
        tester.getRect(find.byKey(const ValueKey('editor-compact-close'))).left,
        greaterThanOrEqualTo(adapted.left),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('editor-compact-more'))).right,
        lessThanOrEqualTo(390 - adapted.right),
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('storefront_content_viewport'))),
        const Rect.fromLTWH(
          0,
          WebsiteEditorChromeGeometry.topBarHeight,
          390,
          844 - WebsiteEditorChromeGeometry.topBarHeight,
        ),
      );
    });
  });

  group('Guardar tiene un solo owner', () {
    testWidgets('llama al comando del scope, nunca a un coordinador propio',
        (tester) async {
      await pumpEditor(tester, width: 390);

      await tester.tap(find.byKey(const ValueKey('editor-compact-save')));
      await tester.pump();

      expect(saveCalls, 1);
    });

    testWidgets('sin cambios queda inerte', (tester) async {
      await pumpEditor(tester, width: 390, dirty: false);

      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('editor-compact-save')),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('mientras guarda no admite un segundo envío y lo muestra',
        (tester) async {
      await pumpEditor(tester, width: 390, isSaving: true);

      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey('editor-compact-save')),
      );
      expect(save.onPressed, isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('editor-compact-save')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(saveCalls, 0);
    });
  });

  group('el desborde conserva TODAS las capacidades', () {
    testWidgets(
        'la hoja de acciones agrupa navegación, página, tienda y '
        'descartar', (tester) async {
      await pumpEditor(tester, width: 390);

      await tester.tap(find.byKey(const ValueKey('editor-compact-more')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('editor-compact-actions-sheet')),
        findsOneWidget,
      );
      for (final label in const [
        'Escritorio',
        'Tablet',
        'Móvil',
        'Cambiar de página',
        'Nueva página',
        'Capturar página',
        'Editar página',
        'Catálogo web',
        'Páginas',
        'Navegación y menús',
        'Destinos y enlaces',
        'Sitio, tema y contacto',
        'SEO',
        'Integraciones',
        'Dominio y URL',
        'Métodos de pago',
        'Pedidos online',
        'Analytics',
        'Centro del Sitio Web',
        'Abrir tienda pública',
        'Copiar URL',
        'Publicado',
        'Descartar cambios',
      ]) {
        expect(
          find.text(label),
          findsWidgets,
          reason: 'la capacidad "$label" desapareció al compactar la barra',
        );
      }
    });

    testWidgets('cambiar el viewport desde la hoja no escribe datos',
        (tester) async {
      final provider = await pumpEditor(tester, width: 390);
      final blocksBefore = provider.blocks;
      final canUndoBefore = provider.canUndo;

      await tester.tap(find.byKey(const ValueKey('editor-compact-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tablet'));
      await tester.pumpAndSettle();

      expect(provider.devicePreviewMode, DevicePreviewMode.tablet);
      expect(provider.blocks, blocksBefore);
      expect(provider.canUndo, canUndoBefore);
    });

    testWidgets('Descartar usa el comando del scope', (tester) async {
      await pumpEditor(tester, width: 390);

      await tester.tap(find.byKey(const ValueKey('editor-compact-more')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Descartar cambios'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar cambios'));
      await tester.pumpAndSettle();

      expect(discardCalls, 1);
    });

    testWidgets(
        'el switch de publicación delega UNA vez en el owner del '
        'layout y conserva la confirmación', (tester) async {
      await pumpEditor(tester, width: 390);
      expect(website.settingStatements, isEmpty);

      await tester.tap(find.byKey(const ValueKey('editor-compact-more')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('editor-compact-publish-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-compact-publish-switch')),
      );
      await tester.pumpAndSettle();

      // Un solo write, con la clave y el valor que decide el owner. Si la fila
      // compacta volviera a persistir por su cuenta, aquí habría dos.
      expect(website.settingStatements, hasLength(1));
      expect(website.settingStatements.single.tenantId, 'test-tenant');
      expect(
        website.settingStatements.single.settings,
        const <String, String>{'site_published': 'false'},
      );
      // Y el feedback sigue siendo el mismo que da la barra densa.
      expect(find.text('Sitio despublicado'), findsOneWidget);
    });

    testWidgets('la fila compacta de publicación no conoce el servicio',
        (tester) async {
      // El estado y el callback entran; la persistencia no vive aquí. Es lo
      // que impide que vuelva a existir un segundo writer de `site_published`.
      await pumpEditor(tester, width: 390);
      await tester.tap(find.byKey(const ValueKey('editor-compact-more')));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<Switch>(
        find.byKey(const ValueKey('editor-compact-publish-switch')),
      );
      expect(switchWidget.value, isTrue);
      expect(switchWidget.onChanged, isNotNull);
    });

    testWidgets('en Escritorio el alcance queda inerte y dice por qué',
        (tester) async {
      await pumpEditor(tester, width: 390);

      await tester.tap(find.byKey(const ValueKey('editor-compact-more')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Escritorio es la base'),
        findsWidgets,
      );
    });
  });

  group('1440 · la composición de panel queda intacta', () {
    testWidgets('la barra densa consume la misma región sin mover el canvas',
        (tester) async {
      const adapted = EdgeInsets.only(left: 80, right: 40);
      await pumpEditor(
        tester,
        width: 1440,
        height: 900,
        adaptedMargins: adapted,
      );

      expect(
        tester
            .getRect(find.byKey(const ValueKey('editor-dense-nav-menu')))
            .left,
        greaterThanOrEqualTo(adapted.left),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('editor-dense-more'))).right,
        lessThanOrEqualTo(1440 - adapted.right),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('editor-dense-bar'))).width,
        1440,
      );
    });

    testWidgets('conserva la barra densa y sus controles inline, sin desbordar',
        (tester) async {
      await pumpEditor(tester, width: 1440, height: 900);

      // La barra densa sigue siendo la de pane — no la compacta — aunque su
      // navegación viaje en el cajón `O-01` a este ancho.
      expect(find.byKey(const ValueKey('editor-dense-bar')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-dense-nav-menu')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('editor-compact-close')), findsNothing);
      expect(find.byKey(const ValueKey('editor-compact-save')), findsNothing);
      expect(find.byKey(const ValueKey('editor-compact-more')), findsNothing);
      // Los destinos siguen a un clic de distancia.
      await tester.tap(find.byKey(const ValueKey('editor-dense-nav-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Catálogo web'), findsOneWidget);
      expect(find.text('Páginas'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('editor-dense-bar'))).height,
        WebsiteEditorChromeGeometry.topBarHeight,
      );
      // Sin intercepción y sin inflar el viewport: si la barra densa desborda
      // a 1440 con la tipografía real, este test lo dice.
      expect(tester.takeException(), isNull);
    });
  });

  group('la barra densa cabe en el ancho real', () {
    // Dos defectos, una causa: la barra se dibujaba con más contenido del que
    // cabía. En Escritorio el alcance se montaba inerte y `A-01` ponía su
    // explicación bajo el track — `BOTTOM OVERFLOWED BY 8.2 PIXELS` en la
    // ventana real de ~1375 — y la franja de navegación completa junto a las
    // tres autoridades desbordaba a lo ancho (+537 a 1375, +472 a 1440).
    //
    // Aquí no se filtra ni se silencia nada: se capturan TODOS los
    // `FlutterError` del montaje y se exige cero.
    for (final width in const <double>[1050, 1375, 1440, 1920]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'a ${width.toStringAsFixed(0)} en ${brightness.name} no desborda '
          'en ningún eje',
          (tester) async {
            final errors = <String>[];
            final previous = FlutterError.onError;
            FlutterError.onError =
                (details) => errors.add(details.exceptionAsString());
            await pumpEditor(
              tester,
              width: width,
              height: 900,
              brightness: brightness,
            );
            FlutterError.onError = previous;

            expect(errors, isEmpty, reason: errors.join(' · '));
            expect(tester.takeException(), isNull);
            expect(
              tester.getSize(find.byKey(const ValueKey('editor-dense-bar'))),
              Size(width, WebsiteEditorChromeGeometry.topBarHeight),
              reason: 'la barra conserva su altura publicada',
            );
            // Las tres autoridades siguen visibles y caben.
            for (final key in const <ValueKey<String>>[
              ValueKey('editor-viewport-selector'),
              ValueKey('editor-write-scope-base'),
            ]) {
              expect(find.byKey(key), findsOneWidget);
              expect(
                tester.getSize(find.byKey(key)).height,
                lessThanOrEqualTo(WebsiteEditorChromeGeometry.topBarHeight),
              );
            }
            expect(find.text('Vista previa'), findsOneWidget);
          },
        );
      }
    }

    // `O-01` lleva 7 ítems como máximo, así que el menú colapsado es un atajo
    // de destinos, nunca el editor entero. Mientras la navegación esté
    // colapsada el cajón es el ÚNICO sitio donde vive el resto, y por eso no
    // puede desaparecer por ancho: con las autoridades montadas la franja no
    // cabe a ningún ancho, luego el cajón se queda a todo ancho.
    for (final width in const <double>[1375, 1920]) {
      testWidgets(
        'a ${width.toStringAsFixed(0)} en pageEditor el cajón conserva TODAS '
        'las capacidades',
        (tester) async {
          await pumpEditor(tester, width: width, height: 900);

          expect(
            find.byKey(const ValueKey('editor-dense-nav-menu')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('editor-dense-more')),
            findsOneWidget,
            reason: 'con la navegación colapsada el cajón es la única casa '
                'del resto del editor',
          );
          // Las tres autoridades siguen en la barra, separadas.
          expect(
            find.byKey(const ValueKey('editor-viewport-selector')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('editor-write-scope-base')),
            findsOneWidget,
          );
          expect(find.text('Vista previa'), findsOneWidget);

          await tester.tap(find.byKey(const ValueKey('editor-dense-more')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('editor-compact-actions-sheet')),
            findsOneWidget,
          );

          // Un representante de cada capacidad que el menú de 7 no lleva.
          for (final capability in const <String>[
            'SEO',
            'Integraciones',
            'Dominio y URL',
            'Métodos de pago',
            'Pedidos online',
            'Analytics',
            'Abrir feed de productos',
            'Copiar feed de productos',
            'Cambiar de página',
            'Copiar enlace de la página',
            'Abrir la página en otra pestaña',
            'Capturar página',
            'Nueva página',
            'Abrir tienda pública',
            'Copiar URL',
          ]) {
            await tester.scrollUntilVisible(
              find.text(capability),
              120,
              scrollable: find
                  .descendant(
                    of: find.byKey(
                      const ValueKey('editor-compact-actions-sheet'),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            expect(
              find.text(capability),
              findsOneWidget,
              reason: '«$capability» tiene que seguir alcanzable',
            );
          }
          // Y la publicación, que es un interruptor y no una acción.
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('editor-compact-publish-switch')),
            -120,
            scrollable: find
                .descendant(
                  of: find.byKey(
                    const ValueKey('editor-compact-actions-sheet'),
                  ),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(
            find.byKey(const ValueKey('editor-compact-publish-switch')),
            findsOneWidget,
          );

          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('sin autoridades del canvas, el ancho sí despliega la barra',
        (tester) async {
      final provider = await pumpEditor(tester, width: 1920, height: 900);
      provider.openWorkspace(WebsiteWorkspaceMode.catalog);
      await tester.pumpAndSettle();

      expect(find.text('Catálogo web'), findsOneWidget);
      expect(find.text('Estructura'), findsOneWidget);
      expect(find.text('Publicado'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-dense-nav-menu')),
        findsNothing,
        reason: 'sin los tres controles del lienzo la franja sí cabe',
      );
      expect(find.byKey(const ValueKey('editor-dense-more')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en Escritorio dice que se edita el común, y no ofrece elegir',
        (tester) async {
      await pumpEditor(tester, width: 1375, height: 900);

      expect(
        find.byKey(const ValueKey('editor-write-scope-base')),
        findsOneWidget,
        reason: 'el estado base se declara, no se simula un control',
      );
      expect(
        find.byKey(const ValueKey('editor-write-scope-selector')),
        findsNothing,
        reason: 'un grupo sin nada que elegir no se monta inerte en la barra',
      );
      // La razón queda VISIBLE, no sólo en tooltip.
      expect(find.textContaining('Escritorio es la base'), findsOneWidget);
      expect(find.text('Común'), findsOneWidget);
      // El estado se anuncia entero, con la frase completa de t10 10a.
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('editor-write-scope-base')))
            .label,
        contains('Cambia a Tablet o Móvil para crear un override'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('en Tablet y en Móvil el selector sigue operativo y separado',
        (tester) async {
      final provider = await pumpEditor(tester, width: 1375, height: 900);

      for (final mode in const <DevicePreviewMode>[
        DevicePreviewMode.tablet,
        DevicePreviewMode.mobile,
      ]) {
        provider.setDevicePreviewMode(mode);
        await tester.pumpAndSettle();

        final selector = find.byKey(
          const ValueKey('editor-write-scope-selector'),
        );
        expect(selector, findsOneWidget);
        expect(
          find.byKey(const ValueKey('editor-write-scope-base')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('editor-viewport-selector')),
          findsOneWidget,
          reason: 'viewport y alcance siguen siendo autoridades separadas',
        );
        expect(
          tester.widget<VbSegmented<WebsiteWriteScope>>(selector).onChanged,
          isNotNull,
          reason: 'en ${mode.name} el alcance sí se elige',
        );
        expect(
          tester.getSize(selector).height,
          lessThanOrEqualTo(WebsiteEditorChromeGeometry.topBarHeight),
          reason: 'operativo también cabe en la barra',
        );
      }

      // Y volver a Escritorio devuelve el alcance a Común, sin dejar un
      // override activo que nadie podría cambiar desde ahí.
      provider.setDevicePreviewMode(DevicePreviewMode.desktop);
      await tester.pumpAndSettle();
      expect(provider.writeScope, WebsiteWriteScope.shared);
      expect(
        find.byKey(const ValueKey('editor-write-scope-selector')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('834 · tablet usa la composición contextual', () {
    testWidgets('bajo 1050 la barra es la compacta, no un panel comprimido',
        (tester) async {
      await pumpEditor(tester, width: 834, height: 640);

      expect(find.byKey(const ValueKey('editor-compact-more')), findsOneWidget);
      expect(find.text('Catálogo web'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
