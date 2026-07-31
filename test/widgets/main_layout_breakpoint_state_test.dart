import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'routed child keeps one state instance across desktop and compact shells',
    (tester) async {
      final navigation = NavigationService();
      final workspaces = WorkspaceManager(
        sessionIdentity: 'main-layout-breakpoint-state-test',
      );
      final appearance = AppearanceService();
      final chat = ChatProvider();
      final workspace = workspaces.activeWorkspace!
        ..isPinned = true
        ..pinnedRouteRoot = '/hr';
      final initialized = ValueNotifier<int>(0);
      final disposed = ValueNotifier<int>(0);

      addTearDown(navigation.dispose);
      addTearDown(workspaces.dispose);
      addTearDown(appearance.dispose);
      addTearDown(chat.dispose);
      addTearDown(initialized.dispose);
      addTearDown(disposed.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 800);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavigationService>.value(value: navigation),
            ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
            ChangeNotifierProvider<AppearanceService>.value(value: appearance),
            ChangeNotifierProvider<ChatProvider>.value(value: chat),
            Provider<Workspace>.value(value: workspace),
          ],
          child: MaterialApp(
            home: MainLayout(
              title: 'Prueba de estado',
              body: _StateProbe(
                initialized: initialized,
                disposed: disposed,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(initialized.value, 1);
      expect(disposed.value, 0);
      expect(find.text('contador 0'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('state-probe-increment')));
      await tester.pump();
      expect(find.text('contador 1'), findsOneWidget);

      tester.view.physicalSize = const Size(899, 800);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('main-layout-compact-header')),
          findsOneWidget);
      expect(find.byType(_StateProbe), findsOneWidget);
      expect(find.text('contador 1'), findsOneWidget);
      expect(initialized.value, 1);
      expect(disposed.value, 0);

      tester.view.physicalSize = const Size(1000, 800);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('main-layout-compact-header')),
          findsNothing);
      expect(find.byType(_StateProbe), findsOneWidget);
      expect(find.text('contador 1'), findsOneWidget);
      expect(initialized.value, 1);
      expect(disposed.value, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(disposed.value, 1);
    },
  );
}

class _StateProbe extends StatefulWidget {
  const _StateProbe({
    required this.initialized,
    required this.disposed,
  });

  final ValueNotifier<int> initialized;
  final ValueNotifier<int> disposed;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  var _counter = 0;

  @override
  void initState() {
    super.initState();
    widget.initialized.value += 1;
  }

  @override
  void dispose() {
    widget.disposed.value += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        key: const ValueKey('state-probe-increment'),
        onPressed: () => setState(() => _counter += 1),
        child: Text('contador $_counter'),
      ),
    );
  }
}
