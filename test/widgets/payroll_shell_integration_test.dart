import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/payroll/payroll_redesign_page.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_advances_and_cash_surfaces.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/models/current_user_profile.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/notification_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/smart_screenshot_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/workspace_chrome_theme.dart';
import 'package:vinabike_erp/shared/utils/responsive_viewport.dart';
import 'package:vinabike_erp/shared/widgets/main_layout.dart';
import 'package:vinabike_erp/shared/widgets/right_toolbar.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';
import 'package:vinabike_erp/shared/widgets/workspace_tab_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'right_toolbar_over_content': false,
    });
  });

  testWidgets(
    '1440 rail reserves the real toolbar width without duplicate chrome',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(1440, 900),
        chromeMode: NavigationChromeMode.rail,
      );

      expect(find.byType(AppNavigationRail), findsOneWidget);
      expect(
        tester.getSize(find.byType(AppNavigationRail)).width,
        WorkspaceShellScope.navigationRailWidth,
      );
      expect(find.byType(AppSidebar), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('reserved-right-toolbar'))),
        const Size(RightToolbar.collapsedWidth, 900),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('payroll-route-content')))
            .width,
        closeTo(
          1440 -
              RightToolbar.collapsedWidth -
              WorkspaceShellScope.navigationRailWidth -
              1,
          0.01,
        ),
      );
      _expectSingleShellIdentity(tester, rail: true);
      _expectNoWhiteWorkspaceActionIsland(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '1440 expanded sidebar leaves the integral Payroll surface usable',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(1440, 900),
        chromeMode: NavigationChromeMode.expanded,
      );

      expect(find.byType(AppSidebar), findsOneWidget);
      expect(find.byType(AppNavigationRail), findsNothing);
      expect(
        tester.getSize(find.byType(AppSidebar)).width,
        closeTo(280, 0.01),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('payroll-route-content')))
            .width,
        closeTo(1440 - RightToolbar.collapsedWidth - 280 - 1, 0.01),
      );
      _expectSingleShellIdentity(tester, rail: false);
      _expectNoWhiteWorkspaceActionIsland(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '900 keeps desktop chrome; 899/834 keep the 5m table with compact chrome; '
    '390 uses task cards',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(900, 900),
        chromeMode: NavigationChromeMode.rail,
      );
      expect(find.byType(WorkspaceTabBar), findsOneWidget);
      expect(find.byType(AppNavigationRail), findsOneWidget);
      expect(
          find.byKey(const ValueKey('reserved-right-toolbar')), findsOneWidget);
      expect(find.byKey(const ValueKey('payroll-mobile-weeks')), findsNothing);
      expect(tester.takeException(), isNull);

      for (final size in const <Size>[
        Size(899, 900),
        Size(834, 900),
        Size(390, 844),
      ]) {
        await harness.resize(tester, size);

        expect(find.byType(WorkspaceTabBar), findsNothing, reason: '$size');
        expect(find.byType(AppNavigationRail), findsNothing, reason: '$size');
        expect(find.byType(AppSidebar), findsNothing, reason: '$size');
        expect(
          find.byKey(const ValueKey('reserved-right-toolbar')),
          findsNothing,
          reason: '$size',
        );
        // `5m` separa las dos preguntas: bajo 900 el CHROME es compacto —header
        // único con drawer, sin rail ni tabs— pero el CONTENIDO sólo pasa a
        // tarjetas en teléfono. En la banda de tablet (834/899) sigue siendo la
        // tabla de cuatro columnas, porque hay ancho de sobra para persona,
        // total, a pagar y decisión.
        final phone = size.width < 720;
        // `payroll-mobile-weeks` es la píldora de alcance, o sea CHROME: 5m la
        // conserva en toda la banda compacta, tablet incluida.
        expect(
          find.byKey(const ValueKey('payroll-mobile-weeks')),
          findsOneWidget,
          reason: '$size · el alcance compacto es chrome, no contenido',
        );
        expect(
          find.byKey(const ValueKey('payroll-queue-vertical-scroll')),
          phone ? findsNothing : findsOneWidget,
          reason: '$size · 5m mantiene la tabla en la banda de tablet',
        );
        expect(tester.takeException(), isNull, reason: '$size');
      }
    },
  );

  testWidgets(
    'compact chrome contains every palette across outer light and dark themes',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);
      final unread = NotificationService().unreadNotificationsCount;
      unread.value = 3;
      addTearDown(() => unread.value = 0);
      harness.toolbar.openTool(ToolbarTool.notifications);

      for (final palette in AppearanceService.sidebarPalettes) {
        for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
          await harness.pump(
            tester,
            size: const Size(390, 844),
            chromeMode: NavigationChromeMode.rail,
            paletteCode: palette.code,
            themeMode: mode,
          );

          final expectedChrome = WorkspaceChromeTheme.resolve(
            palette: palette,
            brightness:
                mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
          );

          // Ya no hay que elegir modo: el drawer es sólo navegación.
          final scaffoldState = await _openCompactDrawer(tester);
          await tester.pumpAndSettle();

          final drawer = tester.widget<Drawer>(
            find.byKey(const ValueKey('main-layout-mobile-drawer')),
          );
          expect(
            drawer.backgroundColor,
            expectedChrome.canvas,
            reason: '${palette.code}/${mode.name} drawer',
          );

          final searchFinder =
              find.byKey(const ValueKey('mobile-drawer-search'));
          final scopedTheme = Theme.of(tester.element(searchFinder));
          expect(scopedTheme.colorScheme.surface, expectedChrome.canvas);
          expect(
            scopedTheme.colorScheme.surfaceContainerHighest,
            expectedChrome.raised,
          );
          expect(
            scopedTheme.inputDecorationTheme.fillColor,
            expectedChrome.raised,
          );
          expect(
            scopedTheme.colorScheme.onSurface,
            expectedChrome.foreground,
          );
          expect(
            scopedTheme.colorScheme.onSurfaceVariant,
            expectedChrome.mutedForeground,
          );

          expect(
            tester.getSize(
              find.byKey(const ValueKey('mobile-drawer-close')),
            ),
            const Size(48, 48),
          );

          // La campana quedó dedicada a notificaciones desde el 2026-08-20;
          // el contador combinado se repartió en tres íconos con nombre.
          final activity = find.byKey(
            const ValueKey('main-layout-mobile-notifications'),
          );
          final badgeText = tester.widget<Text>(
            find.descendant(of: activity, matching: find.text('3')),
          );
          expect(badgeText.style?.color, expectedChrome.onAttention);
          final badgeContainer = tester.widget<Container>(
            find
                .descendant(of: activity, matching: find.byType(Container))
                .last,
          );
          expect(
            (badgeContainer.decoration! as BoxDecoration).color,
            expectedChrome.attention,
          );

          // Las herramientas salieron del drawer y viven en la hoja del tercer
          // ícono del encabezado. La herramienta abierta se sigue marcando.
          scaffoldState.closeDrawer();
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('main-layout-mobile-workspaces')),
          );
          await tester.pumpAndSettle();
          final selectedTool = tester.widget<ListTile>(
            find.byKey(const ValueKey('compact-tools-notifications')),
          );
          expect(selectedTool.selected, isTrue);
          Navigator.of(
            tester.element(
              find.byKey(const ValueKey('compact-tools-notifications')),
            ),
          ).pop();
          await tester.pumpAndSettle();
          await _openCompactDrawer(tester);
          await tester.pumpAndSettle();

          final scaffold = tester.widget<Scaffold>(
            find
                .ancestor(
                  of: find.byKey(
                    const ValueKey('main-layout-mobile-menu'),
                  ),
                  matching: find.byType(Scaffold),
                )
                .first,
          );
          expect(
            scaffold.drawerScrimColor,
            isNot(Colors.black.withValues(alpha: 0.42)),
          );
          expect(tester.takeException(), isNull);
          scaffoldState.closeDrawer();
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'compact appearance selector preserves ThemeMode.system explicitly',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      for (final brightness in const [
        Brightness.dark,
        Brightness.light,
      ]) {
        await harness.pump(
          tester,
          size: const Size(390, 844),
          chromeMode: NavigationChromeMode.rail,
          themeMode: ThemeMode.system,
          platformBrightness: brightness,
        );
        // El selector salió del modo Herramientas del drawer y vive en la hoja
        // «Apariencia» del pie, junto a la paleta: en el teléfono la paleta no
        // se podía elegir en ningún lado.
        final scaffoldState = await _openCompactDrawer(tester);
        await tester.tap(
          find.byKey(const ValueKey('mobile-drawer-appearance')),
        );
        await tester.pumpAndSettle();

        final selector = tester.widget<SegmentedButton<ThemeMode>>(
          find.byKey(const ValueKey('theme-mode-selector')),
        );
        expect(selector.selected, const <ThemeMode>{ThemeMode.system});
        expect(harness.appearance.themeMode, ThemeMode.system);
        expect(find.byKey(const ValueKey('theme-mode-system')), findsOneWidget);
        expect(find.byKey(const ValueKey('theme-mode-light')), findsOneWidget);
        expect(find.byKey(const ValueKey('theme-mode-dark')), findsOneWidget);

        final darkMode = find.byKey(const ValueKey('theme-mode-dark'));
        await tester.tap(darkMode);
        await tester.pumpAndSettle();
        expect(harness.appearance.themeMode, ThemeMode.dark);

        await tester.tap(find.byKey(const ValueKey('theme-mode-system')));
        await tester.pumpAndSettle();
        expect(harness.appearance.themeMode, ThemeMode.system);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(darkMode)).pop();
        await tester.pumpAndSettle();
        scaffoldState.closeDrawer();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'selected scope and week survive real desktop-shell resizing',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(1440, 900),
        chromeMode: NavigationChromeMode.rail,
      );

      await tester.tap(
        find.byKey(const ValueKey('payroll-week-card-Semana 29')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(
              find.byKey(
                const ValueKey('payroll-week-card-Semana 29'),
              ),
            )
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(find.textContaining('Semana 29'), findsWidgets);

      await harness.resize(tester, const Size(1116, 900));
      expect(
        tester
            .getSemantics(
              find.byKey(
                const ValueKey('payroll-week-card-Semana 29'),
              ),
            )
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );

      await tester.tap(
        find.text('Anticipos').first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.text('Anticipos').first)
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );

      await harness.resize(tester, const Size(900, 900));
      expect(
        tester
            .getSemantics(find.text('Anticipos').first)
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(find.byType(PayrollAdvancesSurface), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '390 compact shell owns one semantic navy 56px header',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );

      final headerFinder = find.byKey(
        const ValueKey('main-layout-compact-header'),
      );
      expect(headerFinder, findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);

      final header = tester.widget<AppBar>(headerFinder);
      expect(header.toolbarHeight, 56);
      expect(
        header.backgroundColor,
        WorkspaceChromeStyleData.vinabike.canvas,
      );
      expect(header.backgroundColor, isNot(Colors.white));
      expect(
        find.descendant(
          of: headerFinder,
          matching: find.text('Nóminas'),
        ),
        findsOneWidget,
      );
      final title = tester.widget<Text>(
        find.descendant(
          of: headerFinder,
          matching: find.text('Nóminas'),
        ),
      );
      expect(
        title.style?.color,
        WorkspaceChromeStyleData.vinabike.foreground,
        reason:
            'Compact titles are semantic shell content, never pre-styled light-surface widgets.',
      );
      expect(
        find.text('Nóminas'),
        findsOneWidget,
        reason: 'The feature must not repeat the shell-owned mobile title.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in const <double>[390, 430]) {
    testWidgets(
      'compact drawer keeps a 62px reveal and caps at 348px at ${width}px',
      (tester) async {
        final harness = await _ShellHarness.create();
        addTearDown(harness.dispose);

        await harness.pump(
          tester,
          size: Size(width, 844),
          chromeMode: NavigationChromeMode.rail,
          routeAware: true,
        );
        await tester.tap(
          find.byKey(const ValueKey('main-layout-mobile-menu')),
        );
        await tester.pumpAndSettle();

        final drawer = find.byType(Drawer);
        expect(drawer, findsOneWidget);
        expect(
          tester.getSize(drawer).width,
          closeTo(math.min(width - 62, 348), 0.01),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'compact drawer orders identity and search like Design frame 6b',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );
      await tester.tap(
        find.byKey(const ValueKey('main-layout-mobile-menu')),
      );
      await tester.pumpAndSettle();

      final profile = find.byKey(
        const ValueKey('mobile-drawer-identity'),
      );
      final search = find.byKey(
        const ValueKey('mobile-drawer-search'),
      );
      expect(profile, findsOneWidget);
      expect(search, findsOneWidget);
      // El conmutador Navegación/Herramientas se retiró: el drawer es sólo
      // navegación desde el 2026-08-20.
      expect(
        find.byKey(const ValueKey('mobile-drawer-mode-switch')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: profile,
          matching: find.text('Claudio Catalán'),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(search).height, greaterThanOrEqualTo(48));
      expect(
        find.descendant(
          of: search,
          matching: find.byType(EditableText),
        ),
        findsOneWidget,
      );
      // Sin el conmutador en medio, el orden es identidad y luego buscador.
      expect(
        tester.getTopLeft(profile).dy,
        lessThan(tester.getTopLeft(search).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  /// El buscador del drawer contestaba «No encontramos módulos o páginas» a
  /// `Nomina`, es decir, negaba un módulo que existe, sólo porque en un teléfono
  /// nadie teclea la tilde. Lo que se afirma acá es que la tilde deja de ser
  /// requisito **sin** que el buscador deje de filtrar.
  testWidgets(
    'compact drawer search ignores accents and keeps filtering',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );
      await tester.tap(
        find.byKey(const ValueKey('main-layout-mobile-menu')),
      );
      await tester.pumpAndSettle();

      final search = find.byKey(const ValueKey('mobile-drawer-search'));
      final results = find.byKey(
        const ValueKey('mobile-drawer-search-results'),
      );

      await tester.enterText(search, 'Nomina');
      await tester.pumpAndSettle();
      expect(results, findsOneWidget);
      expect(
        find.descendant(of: results, matching: find.text('Nóminas')),
        findsOneWidget,
        reason: 'Nobody types the accent on a phone.',
      );
      expect(
        find.byKey(const ValueKey('mobile-drawer-navigation-mode')),
        findsNothing,
        reason: 'An active query replaces the navigation tree.',
      );

      await tester.enterText(search, 'NÓMINA');
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: results, matching: find.text('Nóminas')),
        findsOneWidget,
        reason: 'Accent and case must reach the same result.',
      );

      await tester.enterText(search, 'Inventario');
      await tester.pumpAndSettle();
      expect(results, findsOneWidget);
      expect(
        find.descendant(of: results, matching: find.text('Nóminas')),
        findsNothing,
        reason: 'Folding accents must not turn the filter into a catalogue.',
      );

      await tester.enterText(search, 'zzzz');
      await tester.pumpAndSettle();
      expect(results, findsNothing);
      expect(
        find.textContaining('No encontramos módulos o páginas'),
        findsOneWidget,
        reason: 'A query with no match still says so.',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    // 2026-08-20 · decisión del dueño: «saca del drawer tanto herramientas
    // como el manejo de workspaces». El drawer queda sólo navegación, y las
    // herramientas viven en la hoja del tercer ícono del encabezado. Antes
    // había dos caminos al mismo sitio.
    'compact drawer is navigation only and its footer targets are 48px',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );
      await tester.tap(
        find.byKey(const ValueKey('main-layout-mobile-menu')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mobile-drawer-mode-navigation')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mobile-drawer-mode-tools')),
        findsNothing,
      );
      // Apariencia baja al pie junto a Configuración: el tema y la paleta no
      // se perdieron al retirar el modo Herramientas.
      final appearance = find.byKey(
        const ValueKey('mobile-drawer-appearance'),
      );
      expect(appearance, findsOneWidget);
      expect(
        tester.getSize(appearance).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact drawer expands RR.HH. and marks the current Payroll destination',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );
      await tester.tap(
        find.byKey(const ValueKey('main-layout-mobile-menu')),
      );
      await tester.pumpAndSettle();

      final hr = find.byKey(const ValueKey('drawer-hr'));
      await tester.scrollUntilVisible(
        hr,
        180,
        scrollable: find.descendant(
          of: find.byKey(
            const ValueKey('mobile-drawer-navigation-mode'),
          ),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(hr, findsOneWidget);
      final activePayroll = find.descendant(
        of: hr,
        matching: find.text('Nóminas'),
      );
      expect(
        activePayroll,
        findsOneWidget,
        reason: 'The current RR.HH. section must open around Payroll.',
      );
      final activeSemantics = find.ancestor(
        of: activePayroll,
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      );
      expect(
        activeSemantics,
        findsOneWidget,
        reason: 'Nóminas must expose its selected state semantically.',
      );

      // El drawer ya no tiene modo Herramientas: es sólo navegación.
      expect(
        find.byKey(const ValueKey('mobile-drawer-mode-tools')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    // 2026-08-20 · las herramientas salieron del drawer y del panel de
    // Actividad: viven en la hoja del tercer ícono del encabezado, que abre
    // directamente en Herramientas y tiene una pestaña para las tareas.
    'the third header icon opens Tools directly, with a Tasks tab',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );
      await tester.tap(
        find.byKey(const ValueKey('main-layout-mobile-workspaces')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tareas y herramientas'), findsOneWidget);
      // Abre en Herramientas, sin un paso intermedio que sólo enlazaba.
      expect(
        find.byKey(const ValueKey('compact-tools-notifications')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compact-workspace-tools-tab-workspaces')),
        findsOneWidget,
      );
      // El drawer ya no participa: es sólo navegación.
      expect(find.byType(Drawer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tapping selected Payroll closes the drawer without duplicating its route',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );
      final initialMatchCount = harness.routeMatchCount;
      expect(harness.currentRoutePath, '/hr/payroll');

      await tester.tap(
        find.byKey(const ValueKey('main-layout-mobile-menu')),
      );
      await tester.pumpAndSettle();
      final navigationScroll = find.descendant(
        of: find.byKey(
          const ValueKey('mobile-drawer-navigation-mode'),
        ),
        matching: find.byType(Scrollable),
      );
      final hr = find.byKey(const ValueKey('drawer-hr'));
      await tester.scrollUntilVisible(
        hr,
        180,
        scrollable: navigationScroll,
      );
      await tester.pumpAndSettle();

      final selectedPayroll = find.descendant(
        of: hr,
        matching: find.text('Nóminas'),
      );
      expect(selectedPayroll, findsOneWidget);
      await tester.tap(selectedPayroll);
      await tester.pumpAndSettle();

      expect(
        find.byType(Drawer),
        findsNothing,
        reason: 'Selecting the current destination must still dismiss chrome.',
      );
      expect(harness.currentRoutePath, '/hr/payroll');
      expect(
        harness.routeMatchCount,
        initialMatchCount,
        reason: 'The current route must not be pushed onto itself.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a compact module badge is a semantic action with a 48px target',
    (tester) async {
      final notificationService = NotificationService();
      notificationService.onlineOrderAlertCount.value = 3;
      addTearDown(() {
        notificationService.onlineOrderAlertCount.value = 0;
      });
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );
      await tester.tap(
        find.byKey(const ValueKey('main-layout-mobile-menu')),
      );
      await tester.pumpAndSettle();

      final navigationScroll = find.descendant(
        of: find.byKey(
          const ValueKey('mobile-drawer-navigation-mode'),
        ),
        matching: find.byType(Scrollable),
      );
      final website = find.byKey(const ValueKey('drawer-website'));
      await tester.scrollUntilVisible(
        website,
        260,
        scrollable: navigationScroll,
      );
      await tester.pumpAndSettle();
      final badgeLabel = find.descendant(
        of: website,
        matching: find.text('3'),
      );
      expect(badgeLabel, findsOneWidget);

      final badgeAction = find.ancestor(
        of: badgeLabel,
        matching: find.byWidgetPredicate((widget) {
          if (widget is! Semantics || widget.properties.button != true) {
            return false;
          }
          final label = (widget.properties.label ?? '').toLowerCase();
          return label.contains('3') && label.contains('pendiente');
        }),
      );
      expect(
        badgeAction,
        findsOneWidget,
        reason: 'The badge needs its own announced button, not plain text.',
      );
      final targetSize = tester.getSize(badgeAction);
      expect(targetSize.width, greaterThanOrEqualTo(48));
      expect(targetSize.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact drawer pins settings and logout in its footer',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );
      await tester.tap(
        find.byKey(const ValueKey('main-layout-mobile-menu')),
      );
      await tester.pumpAndSettle();

      final footer = find.byKey(
        const ValueKey('mobile-drawer-footer'),
      );
      expect(footer, findsOneWidget);
      expect(
        find.descendant(
          of: footer,
          matching: find.text('Configuración'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: footer,
          matching: find.text('Cerrar sesión'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(footer).bottom,
        closeTo(tester.getRect(find.byType(Drawer)).bottom, 1),
        reason: 'Settings and logout must remain pinned at the drawer edge.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Payroll compact scope keeps OCR in overflow instead of a permanent tab',
    (tester) async {
      final harness = await _ShellHarness.create();
      addTearDown(harness.dispose);

      await harness.pump(
        tester,
        size: const Size(390, 844),
        chromeMode: NavigationChromeMode.rail,
        routeAware: true,
      );

      final scopeBar = find.byKey(
        const ValueKey('payroll-mobile-scope-bar'),
      );
      expect(scopeBar, findsOneWidget);
      for (final key in const <String>[
        'payroll-mobile-weeks',
        'payroll-mobile-history',
        'payroll-mobile-advances',
        'payroll-mobile-utilities',
      ]) {
        expect(
          find.descendant(
            of: scopeBar,
            matching: find.byKey(ValueKey(key)),
          ),
          findsOneWidget,
          reason: key,
        );
      }
      expect(
        find.byKey(const ValueKey('payroll-mobile-reconcile')),
        findsNothing,
      );
      expect(find.text('OCR'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('payroll-mobile-utilities')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Importar cartola'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectSingleShellIdentity(
  WidgetTester tester, {
  required bool rail,
}) {
  expect(find.text('Nóminas'), findsWidgets);
  if (rail) {
    expect(find.text('Vinabike'), findsNothing);
  } else {
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Vinabike'),
      ),
      findsOneWidget,
    );
  }
  expect(
    find.descendant(
      of: find.byKey(const ValueKey('payroll-route-content')),
      matching: find.text('Vinabike'),
    ),
    findsNothing,
  );
}

void _expectNoWhiteWorkspaceActionIsland(WidgetTester tester) {
  final actions = tester.widget<Container>(
    find.byKey(const ValueKey('workspace-chrome-actions')),
  );
  final decoration = actions.decoration! as BoxDecoration;
  expect(decoration.color, isNot(Colors.white));
  expect(decoration.border, isNotNull);
}

Future<ScaffoldState> _openCompactDrawer(WidgetTester tester) async {
  final scaffoldFinder = find
      .ancestor(
        of: find.byKey(const ValueKey('main-layout-mobile-menu')),
        matching: find.byType(Scaffold),
      )
      .first;
  final state = tester.state<ScaffoldState>(scaffoldFinder);
  if (state.isDrawerOpen) {
    state.closeDrawer();
    await tester.pumpAndSettle();
  }
  state.openDrawer();
  await tester.pumpAndSettle();
  return state;
}

class _ShellHarness {
  _ShellHarness._({
    required this.manager,
    required this.workspace,
    required this.navigation,
    required this.appearance,
    required this.chat,
    required this.profile,
    required this.toolbar,
    required this.screenshot,
    required this.actions,
  });

  final WorkspaceManager manager;
  final Workspace workspace;
  final NavigationService navigation;
  final AppearanceService appearance;
  final ChatProvider chat;
  final CurrentUserProfileService profile;
  final RightToolbarService toolbar;
  final SmartScreenshotService screenshot;
  final PayrollRedesignActions actions;
  GoRouter? _router;

  String get currentRoutePath =>
      _router!.routerDelegate.currentConfiguration.uri.path;

  int get routeMatchCount =>
      _router!.routerDelegate.currentConfiguration.matches.length;

  static Future<_ShellHarness> create() async {
    final manager = WorkspaceManager(
      sessionIdentity: 'payroll-shell-integration',
    );
    await manager.browserSessionReady;
    final workspaceId = manager.addWorkspace(
      title: 'Nóminas',
      initialRoute: '/hr/payroll',
    );
    final workspace = manager.workspaceById(workspaceId)!;
    final profile = CurrentUserProfileService(
      gateway: _ShellProfileGateway(),
    );
    await profile.synchronize(
      identity: const CurrentUserIdentity(
        id: 'shell-user',
        email: 'claudio@example.com',
        emailVerified: true,
        metadata: {'display_name': 'Claudio Catalán'},
      ),
      resolveTenantId: () async => 'tenant',
    );

    return _ShellHarness._(
      manager: manager,
      workspace: workspace,
      navigation: NavigationService(),
      appearance: AppearanceService(),
      chat: ChatProvider(),
      profile: profile,
      toolbar: RightToolbarService(),
      screenshot: SmartScreenshotService(),
      actions: _payrollActions(),
    );
  }

  /// El tema del arnés es el **del root real** (`lib/main.dart`): resuelve el
  /// preset seleccionado en `AppearanceService` en claro y en oscuro.
  ///
  /// Antes eran `ThemeData.light()` / `ThemeData.dark()`, y con eso el arnés
  /// no representaba a la app: sin el resolver no existe `VinabikeThemeRoles`,
  /// así que ningún componente compartido puede montarse acá — lo destapó el
  /// esqueleto `X-01` de la carga, que se negó a pintar (2026-08-01). Además
  /// una prueba que dice cruzar «todas las paletas» sólo estaba cruzando el
  /// tema anidado del chrome.
  static ThemeData _light(AppearanceService appearance) => AppTheme.resolve(
        preset: appearance.appearancePreset,
        brightness: Brightness.light,
      );

  static ThemeData _dark(AppearanceService appearance) => AppTheme.resolve(
        preset: appearance.appearancePreset,
        brightness: Brightness.dark,
      );

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required NavigationChromeMode chromeMode,
    bool routeAware = false,
    String? paletteCode,
    ThemeMode themeMode = ThemeMode.light,
    Brightness platformBrightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
    addTearDown(
      tester.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    if (paletteCode != null) {
      await appearance.setSidebarPalette(paletteCode);
    }
    await appearance.setThemeMode(themeMode);
    manager.setWorkspaceChromeMode(workspace.id, chromeMode);
    manager.setWorkspaceDrawerVisible(workspace.id, true);
    workspace.drawerWidth = 280;

    Widget app;
    if (routeAware) {
      _router = GoRouter(
        initialLocation: '/hr/payroll',
        routes: [
          GoRoute(
            path: '/hr/payroll',
            builder: (context, state) => Material(
              child: _ReservedPayrollWorkspaceShell(actions: actions),
            ),
          ),
        ],
      );
      app = MaterialApp.router(
        theme: _light(appearance),
        darkTheme: _dark(appearance),
        themeMode: themeMode,
        routerConfig: _router,
      );
    } else {
      app = MaterialApp(
        theme: _light(appearance),
        darkTheme: _dark(appearance),
        themeMode: themeMode,
        home: Material(
          child: _ReservedPayrollWorkspaceShell(actions: actions),
        ),
      );
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorkspaceManager>.value(value: manager),
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<CurrentUserProfileService>.value(
            value: profile,
          ),
          ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
          ChangeNotifierProvider<SmartScreenshotService>.value(
            value: screenshot,
          ),
          Provider<Workspace>.value(value: workspace),
        ],
        child: app,
      ),
    );
    await tester.pumpAndSettle();
    // WorkspaceManager persists presentation state on a short debounce. The
    // app owns that timer; the test advances it explicitly instead of leaving
    // a fake-async timer pending at teardown.
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  void dispose() {
    _router?.dispose();
    screenshot.dispose();
    toolbar.dispose();
    profile.dispose();
    chat.dispose();
    appearance.dispose();
    navigation.dispose();
    manager.dispose();
  }
}

class _ShellProfileGateway implements CurrentUserProfileGateway {
  @override
  Future<Map<String, dynamic>> getMyErpProfile() async {
    return {
      'userId': 'shell-user',
      'tenantId': 'tenant',
      'profileId': 'shell-profile',
      'role': 'admin',
      'permissions': {
        'access_accounting': true,
        'manage_users': true,
      },
      'employee': null,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> getTenantRows(String tenantId) async {
    return [
      {
        'id': tenantId,
        'shop_name': 'Viñabike',
        'subdomain': 'vinabike',
        'is_active': true,
      },
    ];
  }

  @override
  Future<void> updateAuthDisplayName({
    required String userId,
    required String displayName,
  }) async {}

  @override
  Future<Map<String, dynamic>> updateMyEmployeeContact(
    Map<String, dynamic> patch,
  ) {
    throw UnsupportedError('The compact shell never edits employee contact.');
  }
}

class _ReservedPayrollWorkspaceShell extends StatefulWidget {
  const _ReservedPayrollWorkspaceShell({required this.actions});

  final PayrollRedesignActions actions;

  @override
  State<_ReservedPayrollWorkspaceShell> createState() =>
      _ReservedPayrollWorkspaceShellState();
}

class _ReservedPayrollWorkspaceShellState
    extends State<_ReservedPayrollWorkspaceShell> {
  final GlobalKey _workspaceStackKey = GlobalKey(
    debugLabel: 'payroll-shell-integration-workspace-stack',
  );

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceService>();
    final manager = context.watch<WorkspaceManager>();
    final workspace = manager.activeWorkspace!;
    final chrome = WorkspaceChromeTheme.resolve(
      palette: appearance.sidebarPalette,
      brightness: Theme.of(context).brightness,
    );

    return WorkspaceChromeStyle(
      data: chrome,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = ResponsiveViewport.usesCompactShell(context);
          final route = KeyedSubtree(
            key: _workspaceStackKey,
            child: WorkspaceShellScope(
              topInset: compact ? 0 : WorkspaceShellScope.workspaceBarHeight,
              child: MainLayout(
                title: 'Nóminas',
                body: SizedBox.expand(
                  key: const ValueKey('payroll-route-content'),
                  child: PayrollRedesignPage(actions: widget.actions),
                ),
              ),
            ),
          );

          if (compact) return route;

          final navigationWidth = workspace.isDrawerVisible
              ? workspace.chromeModeOverride == NavigationChromeMode.rail
                  ? WorkspaceShellScope.navigationRailWidth
                  : workspace.drawerWidth
              : 0.0;

          return Stack(
            fit: StackFit.expand,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: route),
                  SizedBox(
                    key: const ValueKey('reserved-right-toolbar'),
                    width: RightToolbar.collapsedWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: WorkspaceShellScope.workspaceBarHeight,
                      ),
                      child: ColoredBox(color: chrome.raised),
                    ),
                  ),
                ],
              ),
              Positioned(
                left: navigationWidth,
                top: 0,
                right: 0,
                height: WorkspaceShellScope.workspaceBarHeight,
                child: const WorkspaceTabBar(),
              ),
            ],
          );
        },
      ),
    );
  }
}

PayrollRedesignActions _payrollActions() {
  const methods = <Map<String, dynamic>>[
    {
      'id': 'transfer',
      'name': 'Transferencia',
      'code': 'transfer',
      'account_id': 'account-transfer',
      'is_active': true,
      'requires_reference': false,
    },
    {
      'id': 'cash',
      'name': 'Efectivo',
      'code': 'cash',
      'account_id': 'account-cash',
      'is_active': true,
      'requires_reference': false,
    },
  ];

  PayrollVoucher voucher({
    required String id,
    required int day,
    required String number,
  }) {
    final lines = <PayrollVoucherLine>[
      PayrollVoucherLine(
        id: '$id-line-vicente',
        voucherId: id,
        employeeId: 'employee-vicente',
        employeeName: 'Vicente Soto',
        workedHours: 38,
        hourlyRate: 4500,
        totalAmount: 171000,
        paymentMethodId: 'transfer',
        settledAmount: 0,
        balance: 171000,
      ),
      PayrollVoucherLine(
        id: '$id-line-guillermo',
        voucherId: id,
        employeeId: 'employee-guillermo',
        employeeName: 'Guillermo Pinto',
        workedHours: 20,
        hourlyRate: 4500,
        totalAmount: 90000,
        paymentMethodId: 'cash',
        settledAmount: 0,
        balance: 90000,
      ),
    ];
    return PayrollVoucher(
      id: id,
      tenantId: 'tenant',
      voucherNumber: number,
      periodStart: DateTime(2026, 7, day),
      periodEnd: DateTime(2026, 7, day + 6),
      totalHours: 58,
      totalAmount: 261000,
      employeeCount: lines.length,
      status: PayrollVoucherStatus.confirmed,
      createdAt: DateTime(2026, 7, day),
      updatedAt: DateTime(2026, 7, day),
      reconciliationVersion: 1,
      lines: lines,
    );
  }

  final vouchers = <PayrollVoucher>[
    voucher(id: 'week-28', day: 6, number: 'NOM-028'),
    voucher(id: 'week-29', day: 13, number: 'NOM-029'),
  ];

  return PayrollRedesignActions(
    load: () async => PayrollRedesignData(
      vouchers: vouchers,
      paymentMethods: methods,
      openAdvances: [
        EmployeeAdvance(
          id: 'advance-1',
          employeeId: 'employee-guillermo',
          amount: 40000,
          amountApplied: 0,
          paidAt: DateTime(2026, 7, 10),
          status: 'open',
          paymentMethodId: 'cash',
          paymentAccountId: 'account-cash',
        ),
      ],
      employees: const [
        {
          'id': 'employee-vicente',
          'full_name': 'Vicente Soto',
        },
        {
          'id': 'employee-guillermo',
          'full_name': 'Guillermo Pinto',
        },
      ],
    ),
    hydrateHistoryVoucher: (voucher) async => voucher,
    commitWeek: (_) async {},
    payLine: ({
      required voucherId,
      required lineId,
      required splits,
      required operationKey,
      required expectedReconciliationVersion,
    }) async {},
    registerAdvance: ({
      required employeeId,
      required employeeName,
      required amount,
      required paymentMethodId,
      required paymentAccountId,
      required paidAt,
      reference,
      notes,
      required reasonCode,
      required reasonExplanation,
      workEndedOn,
      originalReceipt,
      required operationKey,
    }) async {},
  );
}
