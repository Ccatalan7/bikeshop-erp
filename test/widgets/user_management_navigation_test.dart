import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/user_management_navigation.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/utils/responsive_viewport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('compact contextual open restores the exact client origin',
      (tester) async {
    await _setViewport(tester, 899);
    final manager = WorkspaceManager(sessionIdentity: 'users-compact');
    addTearDown(manager.dispose);
    String? routedOpenRequest;
    final router = _buildRouter(
      initialLocation: '/clientes/customer-42?tab=bicicletas&bike_id=bike-7',
      onUsersRoute: (value) => routedOpenRequest = value,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: manager,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final buttonContext =
        tester.element(find.byKey(const ValueKey('manage-customer-access')));
    expect(MediaQuery.sizeOf(buttonContext).width, 899);
    expect(ResponsiveViewport.widthOf(buttonContext), 899);
    UserManagementNavigation.open(
      buttonContext,
      audience: UserManagementAudience.customers,
      target: UserManagementTarget.customer,
      targetId: 'customer-42',
    );
    await tester.pumpAndSettle();

    final request = UserManagementOpenRequest.tryParse(routedOpenRequest);
    expect(routedOpenRequest, isNotNull);
    expect(request?.audience, UserManagementAudience.customers);
    expect(request?.target, UserManagementTarget.customer);
    expect(request?.targetId, 'customer-42');
    expect(find.text('Usuarios enrutados'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/clientes/customer-42?tab=bicicletas&bike_id=bike-7',
    );
  });

  testWidgets('desktop opens one canonical workspace from a pinned module',
      (tester) async {
    await _setViewport(tester, 900);
    final manager = WorkspaceManager(sessionIdentity: 'users-desktop');
    addTearDown(manager.dispose);
    manager.toggleWorkspacePinned(0);
    final router = _buildRouter();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: manager,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    UserManagementNavigation.open(
      tester.element(find.byKey(const ValueKey('manage-customer-access'))),
      audience: UserManagementAudience.customers,
      target: UserManagementTarget.customer,
      targetId: 'customer-42',
    );
    await tester.pump();

    expect(
      manager.workspaces.where(
        (workspace) => workspace.initialRoute == UserManagementNavigation.route,
      ),
      hasLength(1),
    );
    expect(manager.workspaces, hasLength(2));
    await tester.pump(const Duration(milliseconds: 300));
  });
}

GoRouter _buildRouter({
  String? initialLocation,
  ValueChanged<String?>? onUsersRoute,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? '/clientes/customer-42',
    routes: [
      GoRoute(
        path: '/clientes/:id',
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              const Text('Bitácora del cliente'),
              FilledButton(
                key: const ValueKey('manage-customer-access'),
                onPressed: () => UserManagementNavigation.open(
                  context,
                  audience: UserManagementAudience.customers,
                  target: UserManagementTarget.customer,
                  targetId: state.pathParameters['id'],
                ),
                child: const Text('Gestionar acceso'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: UserManagementNavigation.route,
        builder: (context, state) {
          onUsersRoute?.call(state.uri.queryParameters['openRequest']);
          return const Scaffold(body: Text('Usuarios enrutados'));
        },
      ),
    ],
  );
}

Future<void> _setViewport(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 824);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
