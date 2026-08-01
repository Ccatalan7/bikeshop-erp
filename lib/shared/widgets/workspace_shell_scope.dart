import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/vinabike_theme_roles.dart';

/// Geometry owned by the authenticated workspace shell.
///
/// Routed modules consume this scope only to leave room for global chrome.
/// Tests and standalone previews that do not mount the real shell keep a zero
/// inset, so features never invent or duplicate workspace geometry.
class WorkspaceShellScope extends InheritedWidget {
  const WorkspaceShellScope({
    required this.topInset,
    required super.child,
    super.key,
  });

  static const double workspaceBarHeight = 40;
  static const double navigationRailWidth = 56;

  final double topInset;

  static double topInsetOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<WorkspaceShellScope>()
            ?.topInset ??
        0;
  }

  @override
  bool updateShouldNotify(WorkspaceShellScope oldWidget) {
    return topInset != oldWidget.topInset;
  }
}

/// Applies platform insets once at the authenticated workspace boundary.
///
/// Compact composition deliberately preserves the top inset for its canonical
/// [AppBar], which paints behind the status bar and positions the toolbar below
/// it. Wide composition has no AppBar, so the global shell protects its tabs,
/// navigation, content and tools together. Keeping this decision above routed
/// modules prevents feature pages from accumulating competing SafeAreas.
class WorkspaceSystemInsetBoundary extends StatelessWidget {
  const WorkspaceSystemInsetBoundary({
    required this.compact,
    required this.child,
    super.key,
  });

  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SafeArea(
        top: false,
        bottom: false,
        child: child,
      );
    }

    final surface = Theme.of(context).colorScheme.surface;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: vinabikeSystemOverlayStyleFor(surface),
      child: ColoredBox(
        color: surface,
        child: SafeArea(
          bottom: false,
          child: child,
        ),
      ),
    );
  }
}

/// Visual roles for controls painted directly on the workspace chrome.
///
/// This is deliberately a plain [InheritedWidget], not a nested [Theme].
/// Menus, dialogs, sheets and tooltips opened by a chrome action therefore
/// keep the application's normal overlay theme instead of inheriting a navy
/// `ColorScheme`.
class WorkspaceChromeStyle extends InheritedWidget {
  const WorkspaceChromeStyle({
    required this.data,
    required super.child,
    super.key,
  });

  final WorkspaceChromeStyleData data;

  static WorkspaceChromeStyleData? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WorkspaceChromeStyle>()
        ?.data;
  }

  @override
  bool updateShouldNotify(WorkspaceChromeStyle oldWidget) {
    return data != oldWidget.data;
  }
}

@immutable
class WorkspaceChromeStyleData {
  const WorkspaceChromeStyleData({
    required this.canvas,
    required this.raised,
    required this.edge,
    required this.foreground,
    required this.mutedForeground,
    required this.accent,
    required this.onAccent,
    required this.dirty,
    required this.attention,
    this.onAttention = const Color(0xFF08222F),
  });

  /// Canonical Viñabike expression used until the palette resolver owns the
  /// full app theme. Consumers read roles, never feature-owned Payroll tokens.
  static const WorkspaceChromeStyleData vinabike = WorkspaceChromeStyleData(
    canvas: Color(0xFF0C2537),
    raised: Color(0xFF12374E),
    edge: Color(0xFF1B4869),
    foreground: Color(0xFFEDF6FC),
    mutedForeground: Color(0xFF8FA9BD),
    accent: Color(0xFF6FD1F6),
    onAccent: Color(0xFF08222F),
    dirty: Color(0xFFF5B545),
    attention: Color(0xFFF2637A),
    onAttention: Color(0xFF08222F),
  );

  factory WorkspaceChromeStyleData.fromThemeRoles(
    VinabikeThemeRoles roles,
  ) {
    final shell = roles.shell;
    return WorkspaceChromeStyleData(
      canvas: shell.canvas,
      raised: shell.raised,
      edge: shell.edge,
      foreground: shell.foreground,
      mutedForeground: shell.mutedForeground,
      accent: shell.accent,
      onAccent: shell.onAccent,
      dirty: shell.dirty,
      attention: shell.attention,
      onAttention: shell.onAttention,
    );
  }

  final Color canvas;
  final Color raised;
  final Color edge;
  final Color foreground;
  final Color mutedForeground;
  final Color accent;
  final Color onAccent;
  final Color dirty;
  final Color attention;
  final Color onAttention;

  /// La barra de estado del sistema, teñida con el chrome que hay debajo.
  ///
  /// El color sale del rol, así que sigue al preset y al modo claro/oscuro. La
  /// regla vive en un solo sitio: [vinabikeSystemOverlayStyleFor].
  SystemUiOverlayStyle get systemOverlayStyle =>
      vinabikeSystemOverlayStyleFor(canvas);
}
