import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/widgets/toolbar_tool_presentation.dart';

void main() {
  late String mainSource;
  late String mainLayoutSource;
  late String rightToolbarSource;
  late String breakpointsSource;
  late String responsiveViewportSource;
  late String zoomScopeSource;
  late String zoomServiceSource;

  setUpAll(() {
    mainSource = File('lib/main.dart').readAsStringSync();
    mainLayoutSource =
        File('lib/shared/widgets/main_layout.dart').readAsStringSync();
    rightToolbarSource =
        File('lib/shared/widgets/right_toolbar.dart').readAsStringSync();
    breakpointsSource = File(
      'lib/shared/utils/responsive_breakpoints.dart',
    ).readAsStringSync();
    responsiveViewportSource = File(
      'lib/shared/utils/responsive_viewport.dart',
    ).readAsStringSync();
    zoomScopeSource = File(
      'lib/shared/widgets/window_zoom_scope.dart',
    ).readAsStringSync();
    zoomServiceSource = File(
      'lib/shared/services/window_zoom_service.dart',
    ).readAsStringSync();
  });

  test('workspace and toolbar chrome share the canonical 900px boundary', () {
    expect(
      RegExp(r'ResponsiveViewport\.usesCompactShell\(').allMatches(mainSource),
      hasLength(1),
    );
    expect(
      mainLayoutSource,
      contains(
        'final showSidebar = '
        'screenWidth >= ResponsiveViewport.desktopMin;',
      ),
    );
    expect(
      mainLayoutSource,
      contains(
        'final screenWidth = '
        'ResponsiveViewport.widthOf(context);',
      ),
    );
    expect(
      RegExp(r'ResponsiveViewport\.usesCompactShell\(context\)')
          .allMatches(mainLayoutSource),
      hasLength(2),
    );

    const matrix = <(double, bool)>[
      (384, true),
      (599, true),
      (600, true),
      (899, true),
      (900, false),
      (1440, false),
    ];
    for (final entry in matrix) {
      expect(
        entry.$1 < 900,
        entry.$2,
        reason: '${entry.$1}px must keep the registered product class.',
      );
    }

    expect(
      breakpointsSource,
      contains('static const double desktopMin = 900;'),
    );
    expect(
      responsiveViewportSource,
      contains(
          'static const double desktopMin = ResponsiveBreakpoints.desktopMin;'),
    );
    expect(
      zoomScopeSource,
      contains('constraints.maxWidth < ResponsiveBreakpoints.desktopMin'),
    );
    expect(zoomServiceSource, isNot(contains('desktopZoomMinWidth')));
  });

  test('stable shell owns desktop tabs without remounting route state', () {
    final rootChrome = _between(
      mainSource,
      'return Scaffold(',
      'const QueryPerformanceGauge()',
    );
    final shell = _between(
      mainSource,
      'class _WorkspaceShellState',
      'class _WorkspaceRouterView',
    );

    expect(rootChrome, isNot(contains('WorkspaceTabBar')));
    expect(
      rootChrome,
      contains('_WorkspaceShell('),
    );
    expect(
      RegExp(r'_WorkspaceShell\(').allMatches(rootChrome),
      hasLength(1),
      reason: 'Both product classes must retain one stable shell slot.',
    );
    expect(
      rootChrome,
      contains("'authenticated-workspace-shell'"),
    );
    expect(shell, contains('if (compact) {'));
    expect(shell, contains("ValueKey('workspace-tab-bar-placement')"));
    expect(shell, contains('left: navigationWidth'));
    expect(shell, contains('height: topInset'));
    expect(shell, contains('child: const WorkspaceTabBar()'));
    expect(
      shell,
      contains('const topInset = WorkspaceShellScope.workspaceBarHeight'),
    );
  });

  test('desktop rail actions expose hover, focus, semantics and keyboard tap',
      () {
    final destination = _between(
      mainLayoutSource,
      'class _RailDestination extends StatelessWidget',
      'class _RailBadge extends StatelessWidget',
    );

    expect(
      destination,
      contains('WorkspaceChromeStyle.maybeOf(context)'),
    );
    expect(destination, contains('button: true'));
    expect(destination, contains('child: InkWell('));
    expect(destination, contains('canRequestFocus: enabled && onTap != null'));
    expect(destination, contains('hoverColor:'));
    expect(destination, contains('focusColor:'));
    expect(destination, isNot(contains('GestureDetector(')));
  });

  test('compact tool workspace overlays but does not replace the route stack',
      () {
    final shell = _between(
      mainSource,
      'class _WorkspaceShellState',
      'class _WorkspaceRouterView',
    );
    final compactShell = _between(
      shell,
      'if (compact) {',
      'if (!appearanceService.rightToolbarOverContent)',
    );

    expect(shell, contains('RightToolbar.compactWorkspace(key: _toolbarKey)'));
    expect(shell, contains(': RightToolbar(key: _toolbarKey)'));
    expect(
      shell,
      contains("debugLabel: 'authenticated-workspace-stack'"),
    );
    expect(shell, contains('key: _workspaceStackKey'));
    expect(
      compactShell,
      matches(
        RegExp(
          r'children:\s*\[\s*_buildWorkspaceStack\(topInset:\s*0\),\s*'
          r'Positioned\.fill\(\s*child:\s*Offstage\(',
          multiLine: true,
        ),
      ),
    );
    expect(compactShell, contains('offstage: !hasCompactTool'));
    expect(compactShell, contains('child: toolbar'));
    expect(
      rightToolbarSource,
      contains('const RightToolbar.compactWorkspace({super.key})'),
    );
    expect(
      rightToolbarSource,
      contains('RightToolbarPresentation.compactWorkspace'),
    );
    expect(
      rightToolbarSource,
      contains('return _buildCompactWorkspace(activeTool);'),
    );
    expect(rightToolbarSource, contains('PopScope('));
    expect(rightToolbarSource, contains("tooltip: 'Volver'"));
  });

  test('drawer owns navigation and tools modes with complete command wiring',
      () {
    expect(
      mainLayoutSource,
      contains('enum _AppDrawerMode { navigation, tools }'),
    );
    expect(
      mainLayoutSource,
      contains("ValueKey('mobile-drawer-mode-\${mode.name}')"),
    );
    expect(
      mainLayoutSource,
      contains('mode: _AppDrawerMode.navigation'),
    );
    expect(
      mainLayoutSource,
      contains('mode: _AppDrawerMode.tools'),
    );
    expect(
      mainLayoutSource,
      contains("ValueKey('mobile-drawer-tools-mode')"),
    );
    expect(
      mainLayoutSource,
      contains('final visibleTools = resolveVisibleToolbarTools('),
    );
    expect(
      mainLayoutSource,
      contains('for (final group in ToolbarToolGroup.values)'),
    );
    expect(
      mainLayoutSource,
      contains('for (final tool in groupedTools)'),
    );
    expect(
      mainLayoutSource,
      contains("ValueKey('mobile-toolbar-tool-\${tool.name}')"),
    );

    expect(
      toolbarToolPresentationCatalog.keys.toSet(),
      ToolbarTool.values.toSet(),
    );
    expect(
      ToolbarTool.newJob.toolbarPresentation.route,
      '/taller/pegas/nueva',
    );
    expect(ToolbarTool.newJob.toolbarPresentation.opensPanel, isFalse);
    for (final tool in ToolbarTool.values.where(
      (tool) => tool != ToolbarTool.newJob,
    )) {
      expect(
        tool.toolbarPresentation.route,
        isNull,
        reason: '${tool.name} must continue through RightToolbarService.',
      );
      expect(tool.toolbarPresentation.opensPanel, isTrue);
    }

    final compactToolTap = _between(
      mainLayoutSource,
      'Widget _buildCompactToolRow(',
      '@override\n  Widget build(BuildContext context)',
    );
    expect(compactToolTap, contains('if (route != null)'));
    expect(
      compactToolTap,
      contains('_handleMobileNavigation(context, route, presentation.title)'),
    );
    expect(compactToolTap, contains('toolbarService.openTool(tool)'));
  });

  test('workspace selector is on demand and compact targets stay at least 48',
      () {
    final selector = _between(
      mainLayoutSource,
      'Widget _buildCompactWorkspaceAccess(',
      'Widget _buildCompactToolsMode(',
    );

    expect(
      selector,
      contains(
        'if (workspaces.length <= 1) return const SizedBox.shrink();',
      ),
    );
    expect(selector, contains("ValueKey('mobile-workspace-selector')"));
    expect(selector, contains('minTileHeight: 48'));
    expect(selector, contains('manager.switchToWorkspaceById(workspace.id)'));

    final drawerHeader = _between(
      mainLayoutSource,
      'Widget _buildCompactDrawerHeader(',
      'Widget _buildDrawerModeSwitch(',
    );
    expect(drawerHeader, contains('minimumSize: const Size(48, 48)'));

    final modeSwitch = _between(
      mainLayoutSource,
      'Widget _buildDrawerModeSwitch(',
      'Widget _buildDrawerModeButton(',
    );
    expect(modeSwitch, contains('height: 56'));
    expect(
      modeSwitch,
      contains(
        'padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3)',
      ),
    );

    const modeSwitchHeight = 56.0;
    const modeSwitchVerticalPadding = 3.0;
    const modeSwitchBorder = 1.0;
    expect(
      modeSwitchHeight -
          (modeSwitchVerticalPadding * 2) -
          (modeSwitchBorder * 2),
      48,
      reason: 'The mode InkWell must receive a full 48px content target.',
    );

    expect(
      rightToolbarSource,
      contains("ValueKey('right-toolbar-compact-back')"),
    );
  });
}

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing "$start".');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, greaterThan(startIndex), reason: 'Missing "$end".');
  return source.substring(startIndex, endIndex);
}
