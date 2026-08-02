import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/workspace_chrome_theme.dart';
import 'package:vinabike_erp/shared/widgets/calculator_panel.dart';
import 'package:vinabike_erp/shared/widgets/main_layout.dart';
import 'package:vinabike_erp/shared/widgets/right_toolbar.dart';
import 'package:vinabike_erp/shared/widgets/toolbar_tool_presentation.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

/// Lee el estilo que el SISTEMA resolvería para la barra de estado.
///
/// No pregunta por una propiedad declarada en un widget: sondea el árbol de
/// capas en el mismo punto que usa Flutter (`RenderView._updateSystemChrome`),
/// que es el centro horizontal a media altura del inset superior. Esa
/// diferencia es justamente el defecto: el `AppBar` de `MainLayout` seguía
/// declarando su estilo mientras otra superficie lo tapaba y pintaba encima.
SystemUiOverlayStyle? _resolvedStatusBarStyle(WidgetTester tester) {
  final renderView = tester.binding.renderViews.single;
  final layer = renderView.debugLayer;
  if (layer == null) return null;
  return layer.find<SystemUiOverlayStyle>(
    Offset(
      renderView.paintBounds.center.dx,
      tester.view.padding.top / 2.0,
    ),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('shared presentation catalog covers every toolbar tool', () {
    expect(
      toolbarToolPresentationCatalog.keys.toSet(),
      ToolbarTool.values.toSet(),
    );

    final newJob = ToolbarTool.newJob.toolbarPresentation;
    expect(newJob.opensPanel, isFalse);
    expect(newJob.route, '/taller/pegas/nueva');

    for (final tool in ToolbarTool.values.where(
      (tool) => tool != ToolbarTool.newJob,
    )) {
      expect(
        tool.toolbarPresentation.opensPanel,
        isTrue,
        reason: '${tool.name} must keep using its canonical panel.',
      );
    }
  });

  test('desktop and compact shells share one permission projection', () {
    final withoutHr = resolveVisibleToolbarTools(
      canManageHr: false,
      performanceEnabled: true,
      performancePinned: true,
    );
    expect(withoutHr, isNot(contains(ToolbarTool.kiosk)));
    expect(withoutHr, contains(ToolbarTool.performance));

    final withHrWithoutGauge = resolveVisibleToolbarTools(
      canManageHr: true,
      performanceEnabled: true,
      performancePinned: false,
    );
    expect(withHrWithoutGauge, contains(ToolbarTool.kiosk));
    expect(withHrWithoutGauge, isNot(contains(ToolbarTool.performance)));
  });

  testWidgets(
    'compact toolbar is zero-sized while inactive and closes through Back',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final service = RightToolbarService();
      await tester.pumpWidget(
        ChangeNotifierProvider<RightToolbarService>.value(
          value: service,
          child: const MaterialApp(
            home: Scaffold(
              body: RightToolbar.compactWorkspace(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(RightToolbar)), Size.zero);
      expect(find.byKey(const ValueKey('right-toolbar-compact-back')),
          findsNothing);

      service.openTool(ToolbarTool.calculator);
      await tester.pump();

      expect(find.text('Calculadora'), findsOneWidget);
      expect(find.byType(CalculatorPanel), findsOneWidget);

      final back = find.byKey(const ValueKey('right-toolbar-compact-back'));
      expect(back, findsOneWidget);
      final backSize = tester.getSize(back);
      expect(backSize.width, greaterThanOrEqualTo(48));
      expect(backSize.height, greaterThanOrEqualTo(48));

      await tester.tap(back);
      await tester.pump();

      expect(service.activeTool, isNull);
      expect(tester.getSize(find.byType(RightToolbar)), Size.zero);
      expect(find.byType(CalculatorPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system Back closes the compact tool before the host route',
      (tester) async {
    final service = RightToolbarService()..openTool(ToolbarTool.calculator);

    await tester.pumpWidget(
      ChangeNotifierProvider<RightToolbarService>.value(
        value: service,
        child: const MaterialApp(
          home: Scaffold(
            body: RightToolbar.compactWorkspace(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CalculatorPanel), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(service.activeTool, isNull);
    expect(find.byType(CalculatorPanel), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'la herramienta compacta pinta y declara la MISMA franja, y al cerrar '
    'devuelve el estilo del módulo, en 6 presets × 2 modos',
    (tester) async {
      // Inset real de la vista, no una `MediaQueryData` inventada: el sondeo
      // del sistema lee `view.padding`, y sobrescribir `MediaQuery` con una
      // data nueva borraría además el tamaño (trampa ya documentada).
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(384, 824);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);

      final navigation = NavigationService();
      final workspaces = WorkspaceManager(
        sessionIdentity: 'right-toolbar-compact-system-ui-test',
      );
      final appearance = AppearanceService();
      final chat = ChatProvider();
      final toolbar = RightToolbarService();
      final workspace = workspaces.activeWorkspace!
        ..isPinned = true
        ..pinnedRouteRoot = '/taller/pegas';

      addTearDown(navigation.dispose);
      addTearDown(workspaces.dispose);
      addTearDown(appearance.dispose);
      addTearDown(chat.dispose);
      addTearDown(toolbar.dispose);

      for (final preset in AppearancePresets.all) {
        for (final brightness in Brightness.values) {
          final where = '${preset.code}/${brightness.name}';
          final theme = AppTheme.resolve(
            preset: preset,
            brightness: brightness,
          );
          final chrome = WorkspaceChromeTheme.resolveFromTheme(theme);
          final surface = theme.colorScheme.surface;

          toolbar.close();

          // Misma topología que la rama compacta de `_WorkspaceShell`: el
          // módulo abajo y la herramienta a pantalla completa encima.
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<NavigationService>.value(
                  value: navigation,
                ),
                ChangeNotifierProvider<WorkspaceManager>.value(
                  value: workspaces,
                ),
                ChangeNotifierProvider<AppearanceService>.value(
                  value: appearance,
                ),
                ChangeNotifierProvider<ChatProvider>.value(value: chat),
                ChangeNotifierProvider<RightToolbarService>.value(
                  value: toolbar,
                ),
                Provider<Workspace>.value(value: workspace),
              ],
              child: MaterialApp(
                theme: theme,
                themeAnimationDuration: Duration.zero,
                home: WorkspaceChromeStyle(
                  data: chrome,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const MainLayout(
                        title: 'Trabajos',
                        body: SizedBox.expand(),
                      ),
                      Positioned.fill(
                        child: Consumer<RightToolbarService>(
                          builder: (context, service, child) => Offstage(
                            offstage: service.activeTool == null,
                            child: child,
                          ),
                          child: const RightToolbar.compactWorkspace(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          // 1. Con sólo el módulo, la franja es la del chrome del shell.
          final moduleStyle = _resolvedStatusBarStyle(tester);
          expect(
            moduleStyle?.statusBarColor,
            chrome.canvas,
            reason: '$where: la línea base ya no es el header del módulo',
          );
          final moduleLayoutState = tester.state(find.byType(MainLayout));

          // 2. Abrir la herramienta.
          toolbar.openTool(ToolbarTool.calculator);
          await tester.pump();

          final canvas = find.byType(WorkspaceSystemUiCanvas);
          expect(canvas, findsOneWidget, reason: where);
          expect(
            tester.getTopLeft(canvas).dy,
            0,
            reason: '$where: el canvas no llega hasta y=0, así que la franja '
                'del sistema la seguiría pintando el host',
          );
          expect(
            tester.getSize(canvas).height,
            824,
            reason: '$where: el canvas no cubre la ventana completa',
          );

          // Nadie repinta encima del canvas: si el `Material` de adentro
          // volviera a ser opaco, el pixel y el estilo declarado podrían
          // separarse otra vez sin que ningún aserto de estilo lo note.
          final innerMaterial = tester.widget<Material>(
            find.descendant(of: canvas, matching: find.byType(Material)).first,
          );
          expect(
            innerMaterial.color,
            Colors.transparent,
            reason: '$where: la superficie de adentro pinta por su cuenta '
                'encima del canvas que declara el estilo',
          );

          // El inset se consume UNA vez, en el SafeArea interno.
          final header = find.byKey(
            const ValueKey('right-toolbar-compact-header'),
          );
          expect(header, findsOneWidget, reason: where);
          expect(
            tester.getTopLeft(header).dy,
            24,
            reason: '$where: el header no arranca bajo el inset',
          );
          expect(
            tester.getSize(header).height,
            56,
            reason: '$where: la geometría del header cambió',
          );
          expect(
            MediaQuery.paddingOf(tester.element(header)).top,
            0,
            reason: '$where: queda inset por consumir bajo el header, así que '
                'alguien lo consumiría por segunda vez',
          );

          // 3. El estilo publicado describe la superficie que se está viendo.
          final toolStyle = _resolvedStatusBarStyle(tester);
          expect(toolStyle, isNotNull, reason: where);
          expect(
            toolStyle!.statusBarColor,
            surface,
            reason: '$where: la franja declara un color que ya no es el que '
                'esta pantalla pinta',
          );

          final expectDarkIcons = brightness == Brightness.light;
          expect(
            surface.computeLuminance() > 0.5,
            expectDarkIcons,
            reason: '$where: este preset ya no trae el surface que este aserto '
                'asume; revisa la expectativa de brillo, no la fuerces',
          );
          expect(
            toolStyle.statusBarIconBrightness,
            expectDarkIcons ? Brightness.dark : Brightness.light,
            reason: '$where: iconos ilegibles sobre la superficie pintada',
          );
          // Android nombra el brillo del icono, iOS el del fondo: opuestos.
          expect(
            toolStyle.statusBarBrightness,
            isNot(toolStyle.statusBarIconBrightness),
            reason: where,
          );

          // 4. Cerrar devuelve el estilo del módulo, sin rancio ni remount.
          toolbar.close();
          await tester.pump();

          expect(
            find.byType(WorkspaceSystemUiCanvas),
            findsNothing,
            reason: where,
          );
          expect(
            _resolvedStatusBarStyle(tester)?.statusBarColor,
            chrome.canvas,
            reason: '$where: al cerrar la herramienta quedó el estilo rancio '
                'de la superficie que ya no se ve',
          );
          expect(
            identical(tester.state(find.byType(MainLayout)), moduleLayoutState),
            isTrue,
            reason: '$where: la ida y vuelta remontó el módulo',
          );
          expect(tester.takeException(), isNull, reason: where);
        }
      }
    },
  );
}
