import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/current_user_profile_navigation.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('899px pushes profile and Back restores the exact route',
      (tester) async {
    await _setViewport(tester, 899);
    final manager = WorkspaceManager(sessionIdentity: 'profile-compact');
    addTearDown(manager.dispose);
    final router = _buildRouter(
      initialLocation: '/dashboard?view=strategic',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: manager,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-my-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Perfil enrutado'), findsOneWidget);
    expect(manager.workspaces, hasLength(1));

    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Origen Dashboard'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/dashboard?view=strategic',
    );
  });

  testWidgets('900px opens and reuses one dedicated profile workspace',
      (tester) async {
    await _setViewport(tester, 900);
    final manager = WorkspaceManager(sessionIdentity: 'profile-desktop');
    addTearDown(manager.dispose);
    final router = _buildRouter();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: manager,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-my-profile')));
    await tester.pump();

    expect(find.text('Origen Dashboard'), findsOneWidget);
    expect(manager.workspaces, hasLength(2));
    expect(manager.activeWorkspace?.initialRoute, '/profile');
    expect(manager.activeWorkspace?.title, 'Mi perfil');

    await tester.tap(find.byKey(const ValueKey('open-my-profile')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      manager.workspaces.where(
        (workspace) => workspace.initialRoute == '/profile',
      ),
      hasLength(1),
    );
    expect(manager.workspaces, hasLength(2));
  });
}

GoRouter _buildRouter({String initialLocation = '/dashboard'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              const Text('Origen Dashboard'),
              FilledButton(
                key: const ValueKey('open-my-profile'),
                onPressed: () => CurrentUserProfileNavigation.open(context),
                child: const Text('Abrir mi perfil'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const Scaffold(
          body: Text('Perfil enrutado'),
        ),
      ),
    ],
  );
}

Future<void> _setViewport(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
