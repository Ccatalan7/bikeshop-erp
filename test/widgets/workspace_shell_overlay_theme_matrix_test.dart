import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/desktop_update_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/window_zoom_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/themes/workspace_chrome_theme.dart';
import 'package:vinabike_erp/shared/widgets/main_layout.dart';
import 'package:vinabike_erp/shared/widgets/right_toolbar.dart';
import 'package:vinabike_erp/shared/widgets/right_toolbar_glass_surface.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'right_toolbar_blur_enabled': false,
    });
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'right_toolbar_blur_enabled': false,
    });
  });

  testWidgets(
    'right toolbar and sidebar popup keep their intended theme across 6x2',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final services = _ShellServices();
      addTearDown(services.dispose);

      for (final preset in AppearancePresets.all) {
        for (final brightness in Brightness.values) {
          final rootTheme = AppTheme.resolve(
            preset: preset,
            brightness: brightness,
          );
          final chrome = WorkspaceChromeTheme.resolveFromTheme(rootTheme);

          await tester.pumpWidget(
            services.wrap(
              MaterialApp(
                theme: rootTheme,
                themeAnimationDuration: Duration.zero,
                home: Builder(
                  builder: (rootContext) {
                    return WorkspaceChromeStyle(
                      data: chrome,
                      child: Scaffold(
                        body: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 280,
                              child: Theme(
                                data: WorkspaceChromeTheme.sidebarTheme(
                                  Theme.of(rootContext),
                                  chrome,
                                ),
                                child: AppSidebar(
                                  overlayContext: rootContext,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ColoredBox(
                                color: rootTheme.colorScheme.surface,
                              ),
                            ),
                            const RightToolbar(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 30));

          final toolbarSurface = tester.widget<RightToolbarGlassSurface>(
            find.byKey(const ValueKey('right-toolbar-collapsed-surface')),
          );
          expect(
            toolbarSurface.tint,
            brightness == Brightness.dark
                ? rootTheme.colorScheme.surfaceContainerLow
                : rootTheme.colorScheme.surface,
            reason: '${preset.code}/${brightness.name} toolbar neutral surface',
          );
          expect(
            toolbarSurface.border?.left.color,
            rootTheme.colorScheme.outlineVariant,
            reason: '${preset.code}/${brightness.name} toolbar edge',
          );
          expect(
            tester.getSize(
              find.byKey(const ValueKey('right-toolbar-collapsed-surface')),
            ),
            const Size(RightToolbar.collapsedWidth, 900),
            reason: '${preset.code}/${brightness.name} toolbar fills its host',
          );

          await tester.tap(find.byTooltip('Calculadora'));
          await tester.pump(const Duration(milliseconds: 250));
          expect(
            services.rightToolbar.activeTool,
            ToolbarTool.calculator,
            reason: '${preset.code}/${brightness.name} toolbar action',
          );
          final expandedRail = tester.widget<RightToolbarGlassSurface>(
            find.byKey(
              const ValueKey('right-toolbar-expanded-rail-surface'),
            ),
          );
          final expandedPanel = tester.widget<RightToolbarGlassSurface>(
            find.byKey(const ValueKey('right-toolbar-panel-surface')),
          );
          final expandedPanelTheme = Theme.of(
            tester.element(
              find.byKey(const ValueKey('right-toolbar-panel-surface')),
            ),
          );
          expect(
            expandedRail.tint,
            brightness == Brightness.dark
                ? rootTheme.colorScheme.surfaceContainerLow
                : rootTheme.colorScheme.surface,
            reason: '${preset.code}/${brightness.name} expanded neutral rail',
          );
          expect(
            expandedRail.border?.left.color,
            rootTheme.colorScheme.outlineVariant,
            reason: '${preset.code}/${brightness.name} expanded rail edge',
          );
          expect(
            expandedPanel.tint,
            brightness == Brightness.dark
                ? rootTheme.colorScheme.surfaceContainerHigh
                : rootTheme.colorScheme.surface,
            reason: '${preset.code}/${brightness.name} tool panel surface',
          );
          expect(
            expandedPanel.border?.left.color,
            rootTheme.colorScheme.outlineVariant,
            reason: '${preset.code}/${brightness.name} tool panel edge',
          );
          expect(
            expandedPanelTheme.extension<VinabikeThemeRoles>()?.presetCode,
            preset.code,
            reason: '${preset.code}/${brightness.name} tool panel root preset',
          );
          expect(
            expandedPanelTheme.brightness,
            brightness,
            reason: '${preset.code}/${brightness.name} tool panel root mode',
          );
          services.rightToolbar.close();
          await tester.pump(const Duration(milliseconds: 250));

          await tester.tap(
            find.byKey(const ValueKey('sidebar-appearance-entry')),
          );
          await tester.pump(const Duration(milliseconds: 250));

          final popup = find.byKey(const ValueKey('sidebar-options-overlay'));
          expect(
            popup,
            findsOneWidget,
            reason: '${preset.code}/${brightness.name} sidebar popup',
          );
          final popupTheme = Theme.of(tester.element(popup));
          final popupRoles = popupTheme.extension<VinabikeThemeRoles>();
          // 2026-08-20 · decisión del dueño, invierte el contrato anterior.
          // El panel se abría con el tema RAÍZ para no salir navy, y por eso
          // salía blanco SIEMPRE. Pero es el panel donde se elige la paleta: no
          // se podía previsualizar lo elegido. Ahora hereda el tema de la barra
          // y su brillo lo decide la luminancia de la paleta, no el modo
          // claro/oscuro de la app — que es justo lo pedido: «debería tomar la
          // paleta independientemente si está dark mode o light mode».
          expect(
            popupTheme.colorScheme.surface,
            chrome.canvas,
            reason: '${preset.code}/${brightness.name} popup takes the palette',
          );
          expect(
            popupRoles?.presetCode,
            preset.code,
            reason: '${preset.code}/${brightness.name} popup root preset',
          );
          // El menú del riel y el del panel comparten esta regla: cualquier
          // desplegable abierto desde la barra se pinta en su paleta.
          expect(
            popupTheme.colorScheme.onSurface,
            chrome.foreground,
            reason: '${preset.code}/${brightness.name} popup ink follows the '
                'palette, so text stays legible on its own surface',
          );

          Navigator.of(
            tester.element(popup),
            rootNavigator: true,
          ).pop();
          await tester.pump(const Duration(milliseconds: 250));
          expect(popup, findsNothing);
          expect(tester.takeException(), isNull);
        }
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

class _ShellServices {
  _ShellServices()
      : appearance = AppearanceService(),
        chat = ChatProvider(),
        profile = CurrentUserProfileService(),
        desktopUpdate = DesktopUpdateService(),
        navigation = NavigationService(),
        rightToolbar = RightToolbarService(),
        windowZoom = WindowZoomService(),
        workspaces = WorkspaceManager(sessionIdentity: 'shell-theme-test');

  final AppearanceService appearance;
  final ChatProvider chat;
  final CurrentUserProfileService profile;
  final DesktopUpdateService desktopUpdate;
  final NavigationService navigation;
  final RightToolbarService rightToolbar;
  final WindowZoomService windowZoom;
  final WorkspaceManager workspaces;

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppearanceService>.value(value: appearance),
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
        ChangeNotifierProvider<CurrentUserProfileService>.value(value: profile),
        ChangeNotifierProvider<DesktopUpdateService>.value(
          value: desktopUpdate,
        ),
        ChangeNotifierProvider<NavigationService>.value(value: navigation),
        ChangeNotifierProvider<RightToolbarService>.value(value: rightToolbar),
        ChangeNotifierProvider<WindowZoomService>.value(value: windowZoom),
        ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
      ],
      child: child,
    );
  }

  void dispose() {
    appearance.dispose();
    chat.dispose();
    profile.dispose();
    desktopUpdate.dispose();
    navigation.dispose();
    rightToolbar.dispose();
    windowZoom.dispose();
    workspaces.dispose();
  }
}
