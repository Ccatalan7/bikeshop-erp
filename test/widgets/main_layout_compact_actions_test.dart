import 'package:flutter/material.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'a page action in the compact header reads on the chrome in $brightness',
        (tester) async {
      final navigation = NavigationService();
      final workspaces = WorkspaceManager(
        sessionIdentity: 'main-layout-compact-actions-$brightness',
      );
      final appearance = AppearanceService();
      final chat = ChatProvider();
      addTearDown(navigation.dispose);
      addTearDown(workspaces.dispose);
      addTearDown(appearance.dispose);
      addTearDown(chat.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 900);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavigationService>.value(value: navigation),
            ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
            ChangeNotifierProvider<AppearanceService>.value(value: appearance),
            ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ],
          child: MaterialApp(
            theme: AppTheme.resolve(
              preset: AppearancePresets.all.first,
              brightness: brightness,
            ),
            home: MainLayout(
              title: 'Trek Marlin 7',
              onBackPressed: () {},
              compactHeader: MainLayoutCompactHeader(
                title: 'Trek Marlin 7',
                actions: [
                  IconButton(
                    tooltip: 'Editar bicicleta',
                    onPressed: () {},
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byIcon(Icons.edit_outlined));
      final chrome = WorkspaceChromeTheme.resolve(
        palette: appearance.sidebarPalette,
        brightness: brightness,
      );
      final iconColor = tester
          .widget<RichText>(
            find.descendant(
              of: find.byIcon(Icons.edit_outlined),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color;
      expect(context.mounted, isTrue);
      expect(iconColor, chrome.foreground);
      expect(tester.takeException(), isNull);
    });
  }
}
