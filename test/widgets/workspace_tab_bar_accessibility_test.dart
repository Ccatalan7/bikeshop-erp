import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/widgets/browser_workspace_favicon.dart';
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

  testWidgets(
    'unpinned browser workspaces collapse into one keyboard selector',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final semantics = tester.ensureSemantics();
      final manager = WorkspaceManager(
        sessionIdentity: 'workspace-browser-stack-keyboard',
      );
      addTearDown(manager.dispose);
      await manager.browserSessionReady;
      final firstBrowserId = manager.openBrowserWorkspace(
        'https://example.com/orders',
        title: 'Pedidos Example',
      );
      final secondBrowserId = manager.openBrowserWorkspace(
        'https://supplier.example/catalog',
        title: 'Catálogo proveedor',
      );
      expect(firstBrowserId, isNotNull);
      expect(secondBrowserId, isNotNull);
      manager.updateBrowserWorkspaceState(
        firstBrowserId!,
        url: 'https://example.com/orders',
        title: 'Pedidos Example',
        siteName: 'Example',
        faviconUrl: 'https://example.com/favicon.png',
      );
      manager.updateBrowserWorkspaceState(
        secondBrowserId!,
        url: 'https://supplier.example/catalog',
        title: 'Catálogo proveedor',
        siteName: 'Supplier',
        faviconUrl: 'https://supplier.example/favicon.ico',
      );

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

      final browserStack = find.byKey(
        const ValueKey<String>('workspace-browser-stack-tab'),
      );
      expect(browserStack, findsOneWidget);
      expect(
        find.bySemanticsLabel('Pestañas web, 2 abiertas'),
        findsOneWidget,
      );
      final activeFavicon = tester.widget<BrowserWorkspaceFavicon>(
        find.byKey(
          const ValueKey<String>('workspace-browser-stack-active-favicon'),
        ),
      );
      expect(activeFavicon.faviconUrl, 'https://supplier.example/favicon.ico');
      expect(
        find.byKey(
          ValueKey<String>('workspace-tab-control-$firstBrowserId'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          ValueKey<String>('workspace-tab-control-$secondBrowserId'),
        ),
        findsNothing,
      );

      final stackControl = tester.widget<InkWell>(browserStack);
      stackControl.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey<String>('workspace-browser-stack-popover'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>(
            'workspace-browser-stack-favicon-$firstBrowserId',
          ),
        ),
        findsOneWidget,
      );
      final tabRect = tester.getRect(browserStack);
      final extensionRect = tester.getRect(
        find.byKey(
          const ValueKey<String>('workspace-browser-stack-popover'),
        ),
      );
      expect(extensionRect.left, tabRect.left);
      expect(extensionRect.width, tabRect.width - 2);
      expect(extensionRect.top, tabRect.bottom - 1);
      final extensionSurface = tester.widget<Material>(
        find.byKey(
          const ValueKey<String>(
            'workspace-browser-stack-extension-surface',
          ),
        ),
      );
      expect(
        extensionSurface.color,
        WorkspaceChromeStyleData.vinabike.raised,
      );

      // The newest browser is active, so ArrowUp highlights the first row and
      // Enter selects it without relying on hover.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(manager.activeWorkspace?.id, firstBrowserId);

      await tester.tap(browserStack);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey<String>('workspace-browser-stack-pin-$firstBrowserId'),
        ),
      );
      await tester.pumpAndSettle();

      expect(manager.workspaceById(firstBrowserId)?.isPinned, isTrue);
      expect(browserStack, findsNothing);
      expect(
        find.byKey(
          ValueKey<String>('workspace-tab-control-$firstBrowserId'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          ValueKey<String>('workspace-tab-control-$secondBrowserId'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('hover opens the browser stack and each row can close its tab',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final manager = WorkspaceManager(
      sessionIdentity: 'workspace-browser-stack-hover',
    );
    addTearDown(manager.dispose);
    await manager.browserSessionReady;
    final firstBrowserId = manager.openBrowserWorkspace(
      'https://example.com',
      title: 'Example',
    );
    final secondBrowserId = manager.openBrowserWorkspace(
      'https://supplier.example',
      title: 'Supplier',
    );

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

    final browserStack = find.byKey(
      const ValueKey<String>('workspace-browser-stack-tab'),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(browserStack));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('workspace-browser-stack-popover'),
      ),
      findsOneWidget,
    );
    await mouse.moveTo(const Offset(1300, 700));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey<String>('workspace-browser-stack-popover'),
      ),
      findsNothing,
    );

    await mouse.moveTo(tester.getCenter(browserStack));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(
          ValueKey<String>('workspace-browser-stack-item-$firstBrowserId'),
        ),
      ),
    );
    // Crossing from the tab into its attached extension must keep it open
    // beyond the outside-close delay; there is no invisible gap to race.
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(
        const ValueKey<String>('workspace-browser-stack-popover'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey<String>('workspace-browser-stack-close-$firstBrowserId'),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        ValueKey<String>('workspace-browser-stack-close-$firstBrowserId'),
      ),
    );
    await tester.pumpAndSettle();

    expect(manager.workspaceById(firstBrowserId!), isNull);
    expect(browserStack, findsNothing);
    expect(
      find.byKey(
        ValueKey<String>('workspace-tab-control-$secondBrowserId'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('browser stack dismisses on Escape and viewport changes',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final manager = WorkspaceManager(
      sessionIdentity: 'workspace-browser-stack-dismiss',
    );
    addTearDown(manager.dispose);
    await manager.browserSessionReady;
    manager.openBrowserWorkspace('https://one.example', title: 'One');
    manager.openBrowserWorkspace('https://two.example', title: 'Two');

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

    final browserStack = find.byKey(
      const ValueKey<String>('workspace-browser-stack-tab'),
    );
    final popover = find.byKey(
      const ValueKey<String>('workspace-browser-stack-popover'),
    );
    await tester.tap(browserStack);
    await tester.pumpAndSettle();
    expect(popover, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(popover, findsNothing);

    await tester.tap(browserStack);
    await tester.pumpAndSettle();
    expect(popover, findsOneWidget);
    tester.view.physicalSize = const Size(700, 800);
    await tester.pumpAndSettle();
    expect(popover, findsNothing);
  });
}
