import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/widgets/workspace_tab_bar.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'workspace tabs expose focus actions and activate from the keyboard',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final manager = WorkspaceManager(
        sessionIdentity: 'workspace-tab-accessibility',
      );
      addTearDown(manager.dispose);
      await manager.browserSessionReady;

      final dashboard = manager.workspaces.single;
      manager.addWorkspace(
        title: 'Nóminas',
        initialRoute: '/hr/payroll',
      );
      expect(manager.activeWorkspace?.title, 'Nóminas');

      await tester.pumpWidget(
        ChangeNotifierProvider<WorkspaceManager>.value(
          value: manager,
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: WorkspaceTabBar(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dashboardControl = find.byKey(
        ValueKey<String>('workspace-tab-control-${dashboard.id}'),
      );
      expect(dashboardControl, findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp('Espacio de trabajo Dashboard'),
        ),
        findsOneWidget,
      );

      final control = tester.widget<InkWell>(dashboardControl);
      expect(control.focusNode, isNotNull);
      control.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(control.focusNode!.hasFocus, isTrue);

      final pin = find.byKey(
        ValueKey<String>('workspace-tab-pin-${dashboard.id}'),
      );
      final close = find.byKey(
        ValueKey<String>('workspace-tab-close-${dashboard.id}'),
      );
      expect(pin, findsOneWidget);
      expect(close, findsOneWidget);
      expect(tester.getSemantics(pin).label, 'Fijar Dashboard');
      expect(tester.getSemantics(close).label, 'Cerrar Dashboard');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));

      expect(manager.activeWorkspace?.id, dashboard.id);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('workspace tab bar consumes the shell-owned chrome roles',
      (tester) async {
    const chrome = WorkspaceChromeStyleData(
      canvas: Color(0xFF24152B),
      raised: Color(0xFF3A2144),
      edge: Color(0xFF6B3F78),
      foreground: Color(0xFFFFF7FF),
      mutedForeground: Color(0xFFD8C0DF),
      accent: Color(0xFFF0ABFC),
      onAccent: Color(0xFF32113A),
      dirty: Color(0xFFF5B545),
      attention: Color(0xFFF2637A),
    );
    final manager = WorkspaceManager(
      sessionIdentity: 'workspace-tab-custom-chrome',
    );
    addTearDown(manager.dispose);
    await manager.browserSessionReady;

    await tester.pumpWidget(
      ChangeNotifierProvider<WorkspaceManager>.value(
        value: manager,
        child: const MaterialApp(
          home: Scaffold(
            body: WorkspaceChromeStyle(
              data: chrome,
              child: Align(
                alignment: Alignment.topCenter,
                child: WorkspaceTabBar(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('workspace-tab-bar-surface')),
    );
    final decoration = surface.decoration! as BoxDecoration;
    expect(decoration.color, chrome.canvas);
    expect(
      decoration.border!.bottom.color,
      chrome.edge,
    );
  });
}
