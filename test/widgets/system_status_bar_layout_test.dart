import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/workspace_chrome_theme.dart';
import 'package:vinabike_erp/shared/widgets/main_layout.dart';
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
}
