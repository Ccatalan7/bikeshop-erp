import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/window_zoom_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/themes/workspace_chrome_theme.dart';
import 'package:vinabike_erp/shared/widgets/main_layout.dart';
import 'package:vinabike_erp/shared/widgets/window_zoom_scope.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets(
    'el header compacto pinta desde y=0 y conserva el inset superior en 6x2',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final navigation = NavigationService();
      final workspaces = WorkspaceManager(
        sessionIdentity: 'system-status-bar-layout-test',
      );
      final appearance = AppearanceService();
      final chat = ChatProvider();
      final workspace = workspaces.activeWorkspace!
        ..isPinned = true
        ..pinnedRouteRoot = '/taller/pegas';

      addTearDown(navigation.dispose);
      addTearDown(workspaces.dispose);
      addTearDown(appearance.dispose);
      addTearDown(chat.dispose);

      for (final preset in AppearancePresets.all) {
        for (final brightness in Brightness.values) {
          final theme = AppTheme.resolve(
            preset: preset,
            brightness: brightness,
          );
          final chrome = WorkspaceChromeTheme.resolveFromTheme(theme);

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
                Provider<Workspace>.value(value: workspace),
              ],
              child: MaterialApp(
                theme: theme,
                themeAnimationDuration: Duration.zero,
                builder: (context, child) {
                  final media = MediaQuery.of(context);
                  return MediaQuery(
                    data: media.copyWith(
                      padding: const EdgeInsets.only(top: 24),
                      viewPadding: const EdgeInsets.only(top: 24),
                    ),
                    child: child!,
                  );
                },
                home: WorkspaceChromeStyle(
                  data: chrome,
                  child: const MainLayout(
                    title: 'Trabajos',
                    body: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();

          final header = find.byKey(
            const ValueKey('main-layout-compact-header'),
          );
          final appBar = tester.widget<AppBar>(header);
          final where = '${preset.code}/${brightness.name}';

          expect(header, findsOneWidget, reason: where);
          expect(tester.getTopLeft(header).dy, 0, reason: where);
          expect(
            tester.getSize(header).height,
            81,
            reason: '$where debe incluir 24px de status bar, 56px de toolbar '
                'y 1px de divisor',
          );
          expect(appBar.backgroundColor, chrome.canvas, reason: where);
          expect(
            appBar.systemOverlayStyle,
            chrome.systemOverlayStyle,
            reason: where,
          );
          expect(tester.takeException(), isNull, reason: where);
        }
      }
    },
  );

  testWidgets(
    'el boundary deja el inset al AppBar compacto y protege todo el shell ancho',
    (tester) async {
      Future<void> pumpBoundary({required bool compact}) async {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  padding: const EdgeInsets.only(top: 24),
                  viewPadding: const EdgeInsets.only(top: 24),
                ),
                child: child!,
              );
            },
            home: WorkspaceSystemInsetBoundary(
              compact: compact,
              child: const SizedBox.expand(
                key: ValueKey('workspace-inset-probe'),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpBoundary(compact: true);

      var probe = find.byKey(const ValueKey('workspace-inset-probe'));
      expect(tester.getTopLeft(probe).dy, 0);
      expect(MediaQuery.paddingOf(tester.element(probe)).top, 24);

      await tester.binding.setSurfaceSize(const Size(1024, 824));
      await pumpBoundary(compact: false);

      probe = find.byKey(const ValueKey('workspace-inset-probe'));
      expect(tester.getTopLeft(probe).dy, 24);
      expect(MediaQuery.paddingOf(tester.element(probe)).top, 0);
      expect(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'el canvas de sistema pinta desde y=0, publica su contraste y no consume inset',
    (tester) async {
      const surface = Color(0xFFF2F4F7);
      const topInset = 24.0;

      await tester.binding.setSurfaceSize(const Size(384, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                padding: const EdgeInsets.only(top: topInset),
                viewPadding: const EdgeInsets.only(top: topInset),
              ),
              child: child!,
            );
          },
          home: const WorkspaceSystemUiCanvas(
            color: surface,
            child: SafeArea(
              bottom: false,
              child: SizedBox.expand(
                key: ValueKey('system-ui-canvas-content'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final canvas = find.byType(WorkspaceSystemUiCanvas);
      final content = find.byKey(
        const ValueKey('system-ui-canvas-content'),
      );
      final annotation = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(
          of: canvas,
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      final paintedCanvas = tester.widget<ColoredBox>(
        find.descendant(
          of: canvas,
          matching: find.byWidgetPredicate(
            (widget) => widget is ColoredBox && widget.color == surface,
          ),
        ),
      );

      expect(tester.getTopLeft(canvas).dy, 0);
      expect(tester.getTopLeft(content).dy, topInset);
      expect(paintedCanvas.color, surface);
      expect(
        annotation.value,
        vinabikeSystemOverlayStyleFor(surface),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '899/900 conserva el límite físico del status bar aunque el host ancho use zoom',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(899, 824);
      tester.view.padding = const FakeViewPadding(top: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.reset);

      final zoom = WindowZoomService();
      addTearDown(zoom.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<WindowZoomService>.value(
          value: zoom,
          child: MaterialApp(
            builder: (context, child) => WindowZoomScope(child: child!),
            home: const Stack(
              children: [
                WorkspaceSystemInsetBoundary(
                  compact: false,
                  child: SizedBox.expand(
                    key: ValueKey('zoomed-wide-shell-content'),
                  ),
                ),
                WorkspaceTopOverlay(
                  topGap: 10,
                  horizontalMargin: 16,
                  child: Material(
                    child: Center(
                      child: SizedBox(
                        key: ValueKey('zoomed-workspace-alert'),
                        width: 240,
                        height: 40,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      for (final width in <double>[899, 900, 899]) {
        tester.view.physicalSize = Size(width, 824);
        await tester.pump();

        final metrics = tester.widget<WindowViewportMetrics>(
          find.byType(WindowViewportMetrics),
        );
        final clip = find.descendant(
          of: find.byType(WorkspaceTopOverlay),
          matching: find.byType(ClipRect),
        );
        final shellContent = find.byKey(
          const ValueKey('zoomed-wide-shell-content'),
        );
        final alert = find.byKey(
          const ValueKey('zoomed-workspace-alert'),
        );

        expect(
          metrics.appliedScale,
          width < 900 ? 1 : closeTo(0.8, 0.001),
          reason: 'ancho físico $width',
        );
        expect(
          tester.getTopLeft(clip).dy,
          closeTo(24, 0.001),
          reason: '$width: el clip invadió el status bar al escalarse',
        );
        expect(
          tester.getTopLeft(shellContent).dy,
          closeTo(24, 0.001),
          reason: '$width: el SafeArea ancho no llegó al borde físico',
        );
        expect(
          tester.getTopLeft(alert).dy,
          greaterThanOrEqualTo(24),
          reason: '$width: el banner asentado invadió el status bar',
        );
        expect(
          MediaQuery.paddingOf(tester.element(shellContent)).top,
          0,
          reason: '$width: quedó un segundo inset para un descendiente',
        );
        expect(tester.takeException(), isNull, reason: '$width');
      }
    },
  );
}
