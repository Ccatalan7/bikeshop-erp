import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
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

  testWidgets(
    'lo mismo con el workspace SIN fijar y por `child`, que es como lo monta '
    'el router real',
    (tester) async {
      // La prueba de arriba fija el workspace (`isPinned = true`), y eso apaga
      // el drawer: `isDrawerVisible = !isPinnedWorkspace && …`. La app real
      // llega acá **sin fijar**, así que la rama de escritorio monta la barra
      // lateral y la compacta monta un `drawer:` — dos árboles bastante más
      // distintos que los de la prueba anterior. Y el router pasa `child:`,
      // no `body:`.
      //
      // Reproduce lo observado en la app viva el 2026-08-01: a 1360 la
      // conciliación decía «14 movimientos detectados» y a 834 volvía a «Sube
      // la cartola», perdiendo la extracción y 20+ decisiones del operador.
      final navigation = NavigationService();
      final workspaces = WorkspaceManager(
        sessionIdentity: 'main-layout-breakpoint-state-unpinned',
      );
      final appearance = AppearanceService();
      final chat = ChatProvider();
      // La rama SIN fijar monta la barra lateral, y ésa exige dos servicios
      // más que la prueba anterior nunca necesitó.
      final profile = CurrentUserProfileService();
      final toolbar = RightToolbarService();
      final workspace = workspaces.activeWorkspace!;
      final initialized = ValueNotifier<int>(0);
      final disposed = ValueNotifier<int>(0);

      addTearDown(navigation.dispose);
      addTearDown(workspaces.dispose);
      addTearDown(appearance.dispose);
      addTearDown(chat.dispose);
      addTearDown(profile.dispose);
      addTearDown(toolbar.dispose);
      addTearDown(initialized.dispose);
      addTearDown(disposed.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1360, 800);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<NavigationService>.value(value: navigation),
            ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
            ChangeNotifierProvider<AppearanceService>.value(value: appearance),
            ChangeNotifierProvider<ChatProvider>.value(value: chat),
            ChangeNotifierProvider<CurrentUserProfileService>.value(
              value: profile,
            ),
            ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
            Provider<Workspace>.value(value: workspace),
          ],
          child: MaterialApp(
            home: MainLayout(
              title: 'Conciliar nóminas',
              child: _StateProbe(
                initialized: initialized,
                disposed: disposed,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(workspace.isPinned, isFalse);
      expect(initialized.value, 1);
      await tester.tap(find.byKey(const ValueKey('state-probe-increment')));
      await tester.pump();
      expect(find.text('contador 1'), findsOneWidget);

      // 1360 → 834: el mismo salto que hace la app al pasar a tablet.
      tester.view.physicalSize = const Size(834, 1000);
      await tester.pumpAndSettle();

      expect(
        find.text('contador 1'),
        findsOneWidget,
        reason: 'cruzar el breakpoint no puede borrar lo que el operador ya '
            'hizo: en la conciliación eso son la extracción OCR y sus '
            'decisiones',
      );
      expect(disposed.value, 0, reason: 'el State no se destruye, se reubica');
      expect(initialized.value, 1);

      tester.view.physicalSize = const Size(1360, 800);
      await tester.pumpAndSettle();
      expect(find.text('contador 1'), findsOneWidget);
      expect(disposed.value, 0);
      expect(tester.takeException(), isNull);
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
