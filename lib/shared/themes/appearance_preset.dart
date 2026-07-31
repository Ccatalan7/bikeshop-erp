import 'package:flutter/material.dart';

import 'sidebar_palette_option.dart';

/// Foundation seeds for the authenticated workspace chrome.
///
/// These values are resolved into semantic roles before any shell consumer
/// sees them. They intentionally remain separate from the legacy sidebar
/// palette because the original `vinabike` sidebar option was light while the
/// canonical workspace chrome is navy.
@immutable
class AppearanceShellSeed {
  const AppearanceShellSeed({
    required this.canvas,
    required this.raised,
    required this.edge,
    required this.foreground,
    required this.mutedForeground,
    required this.accent,
    required this.onAccent,
    required this.dirty,
    required this.attention,
    required this.onAttention,
  });

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
}

/// Minimum content seeds needed to resolve a complete semantic app theme.
///
/// Surface ladders, state containers and component roles are derived by the
/// central resolver. Feature code must never consume these seeds directly.
@immutable
class AppearanceContentSeed {
  const AppearanceContentSeed({
    required this.primary,
    required this.onPrimary,
    required this.surfaceTint,
  });

  final Color primary;
  final Color onPrimary;
  final Color surfaceTint;
}

/// One complete app appearance preset.
///
/// [legacySidebarPalette] preserves the public API used by existing settings
/// and scoped legacy consumers. New app and shell theming resolves from this
/// preset through `AppTheme`, never from those literal compatibility fields.
@immutable
class AppearancePreset {
  const AppearancePreset({
    required this.legacySidebarPalette,
    required this.shell,
    required this.light,
    required this.dark,
  });

  final SidebarPaletteOption legacySidebarPalette;
  final AppearanceShellSeed shell;
  final AppearanceContentSeed light;
  final AppearanceContentSeed dark;

  String get code => legacySidebarPalette.code;
  String get name => legacySidebarPalette.name;
  String get description => legacySidebarPalette.description;

  AppearanceContentSeed contentSeedFor(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }
}

/// Canonical catalog for the persisted appearance codes.
///
/// Keep codes stable: they are stored in SharedPreferences. Visual evolution
/// changes the seeds behind a code rather than creating feature-local colors.
abstract final class AppearancePresets {
  static const SidebarPaletteOption vinabikeSidebar = SidebarPaletteOption(
    code: 'vinabike',
    name: 'Vinabike',
    description: 'Limpia y luminosa',
    background: Color(0xFFFFFFFF),
    backgroundAlt: Color(0xFFF7FAFC),
    foreground: Color(0xFF111827),
    mutedForeground: Color(0xFF64748B),
    accent: Color(0xFF1976D2),
    onAccent: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
  );

  static const SidebarPaletteOption midnightSidebar = SidebarPaletteOption(
    code: 'midnight',
    name: 'Midnight',
    description: 'Azul negro ejecutivo',
    background: Color(0xFF0E1726),
    backgroundAlt: Color(0xFF14243A),
    foreground: Color(0xFFF8FAFC),
    mutedForeground: Color(0xFFA8B3C7),
    accent: Color(0xFF7DD3FC),
    onAccent: Color(0xFF082F49),
    border: Color(0xFF25344D),
  );

  static const SidebarPaletteOption aubergineSidebar = SidebarPaletteOption(
    code: 'aubergine',
    name: 'Aubergine',
    description: 'Morado Slack premium',
    background: Color(0xFF2B1836),
    backgroundAlt: Color(0xFF432453),
    foreground: Color(0xFFFDF7FF),
    mutedForeground: Color(0xFFD6BFE5),
    accent: Color(0xFFF0ABFC),
    onAccent: Color(0xFF3B0A45),
    border: Color(0xFF573166),
  );

  static const SidebarPaletteOption graphiteSidebar = SidebarPaletteOption(
    code: 'graphite_copper',
    name: 'Graphite',
    description: 'Grafito y cobre',
    background: Color(0xFF1C1917),
    backgroundAlt: Color(0xFF2E241E),
    foreground: Color(0xFFFFF7ED),
    mutedForeground: Color(0xFFD6B69F),
    accent: Color(0xFFF59E0B),
    onAccent: Color(0xFF271703),
    border: Color(0xFF4A372A),
  );

  static const SidebarPaletteOption evergreenSidebar = SidebarPaletteOption(
    code: 'evergreen',
    name: 'Evergreen',
    description: 'Bosque técnico',
    background: Color(0xFF0D241C),
    backgroundAlt: Color(0xFF12382D),
    foreground: Color(0xFFECFDF5),
    mutedForeground: Color(0xFFA7D8C5),
    accent: Color(0xFF5EEAD4),
    onAccent: Color(0xFF042F2E),
    border: Color(0xFF205344),
  );

  static const SidebarPaletteOption pacificSidebar = SidebarPaletteOption(
    code: 'pacific',
    name: 'Pacific',
    description: 'Océano profundo',
    background: Color(0xFF0B2233),
    backgroundAlt: Color(0xFF123A54),
    foreground: Color(0xFFF0F9FF),
    mutedForeground: Color(0xFF9CCBE0),
    accent: Color(0xFF38BDF8),
    onAccent: Color(0xFF082F49),
    border: Color(0xFF1F536E),
  );

  static const AppearancePreset vinabike = AppearancePreset(
    legacySidebarPalette: vinabikeSidebar,
    shell: AppearanceShellSeed(
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
    ),
    light: AppearanceContentSeed(
      primary: Color(0xFF1976D2),
      onPrimary: Color(0xFFFFFFFF),
      surfaceTint: Color(0xFF1976D2),
    ),
    dark: AppearanceContentSeed(
      primary: Color(0xFF6FD1F6),
      onPrimary: Color(0xFF08222F),
      surfaceTint: Color(0xFF1976D2),
    ),
  );

  static const AppearancePreset midnight = AppearancePreset(
    legacySidebarPalette: midnightSidebar,
    shell: AppearanceShellSeed(
      canvas: Color(0xFF0E1726),
      raised: Color(0xFF14243A),
      edge: Color(0xFF25344D),
      foreground: Color(0xFFF8FAFC),
      mutedForeground: Color(0xFFA8B3C7),
      accent: Color(0xFF7DD3FC),
      onAccent: Color(0xFF082F49),
      dirty: Color(0xFFF5B545),
      attention: Color(0xFFF2637A),
      onAttention: Color(0xFF08222F),
    ),
    light: AppearanceContentSeed(
      primary: Color(0xFF285F8A),
      onPrimary: Color(0xFFFFFFFF),
      surfaceTint: Color(0xFF3D78A5),
    ),
    dark: AppearanceContentSeed(
      primary: Color(0xFF7DD3FC),
      onPrimary: Color(0xFF082F49),
      surfaceTint: Color(0xFF3D78A5),
    ),
  );

  static const AppearancePreset aubergine = AppearancePreset(
    legacySidebarPalette: aubergineSidebar,
    shell: AppearanceShellSeed(
      canvas: Color(0xFF2B1836),
      raised: Color(0xFF432453),
      edge: Color(0xFF573166),
      foreground: Color(0xFFFDF7FF),
      mutedForeground: Color(0xFFD6BFE5),
      accent: Color(0xFFF0ABFC),
      onAccent: Color(0xFF3B0A45),
      dirty: Color(0xFFF5B545),
      attention: Color(0xFFF2637A),
      onAttention: Color(0xFF08222F),
    ),
    light: AppearanceContentSeed(
      primary: Color(0xFF7B3C8F),
      onPrimary: Color(0xFFFFFFFF),
      surfaceTint: Color(0xFF8B4A99),
    ),
    dark: AppearanceContentSeed(
      primary: Color(0xFFF0ABFC),
      onPrimary: Color(0xFF3B0A45),
      surfaceTint: Color(0xFF8B4A99),
    ),
  );

  static const AppearancePreset graphite = AppearancePreset(
    legacySidebarPalette: graphiteSidebar,
    shell: AppearanceShellSeed(
      canvas: Color(0xFF1C1917),
      raised: Color(0xFF2E241E),
      edge: Color(0xFF4A372A),
      foreground: Color(0xFFFFF7ED),
      mutedForeground: Color(0xFFD6B69F),
      accent: Color(0xFFF59E0B),
      onAccent: Color(0xFF271703),
      dirty: Color(0xFFF5B545),
      attention: Color(0xFFF2637A),
      onAttention: Color(0xFF08222F),
    ),
    light: AppearanceContentSeed(
      primary: Color(0xFF895000),
      onPrimary: Color(0xFFFFFFFF),
      surfaceTint: Color(0xFFB26A12),
    ),
    dark: AppearanceContentSeed(
      primary: Color(0xFFF5B545),
      onPrimary: Color(0xFF271703),
      surfaceTint: Color(0xFFB26A12),
    ),
  );

  static const AppearancePreset evergreen = AppearancePreset(
    legacySidebarPalette: evergreenSidebar,
    shell: AppearanceShellSeed(
      canvas: Color(0xFF0D241C),
      raised: Color(0xFF12382D),
      edge: Color(0xFF205344),
      foreground: Color(0xFFECFDF5),
      mutedForeground: Color(0xFFA7D8C5),
      accent: Color(0xFF5EEAD4),
      onAccent: Color(0xFF042F2E),
      dirty: Color(0xFFF5B545),
      attention: Color(0xFFF2637A),
      onAttention: Color(0xFF08222F),
    ),
    light: AppearanceContentSeed(
      primary: Color(0xFF0F6B5B),
      onPrimary: Color(0xFFFFFFFF),
      surfaceTint: Color(0xFF12836D),
    ),
    dark: AppearanceContentSeed(
      primary: Color(0xFF5EEAD4),
      onPrimary: Color(0xFF042F2E),
      surfaceTint: Color(0xFF12836D),
    ),
  );

  static const AppearancePreset pacific = AppearancePreset(
    legacySidebarPalette: pacificSidebar,
    shell: AppearanceShellSeed(
      canvas: Color(0xFF0B2233),
      raised: Color(0xFF123A54),
      edge: Color(0xFF1F536E),
      foreground: Color(0xFFF0F9FF),
      mutedForeground: Color(0xFF9CCBE0),
      accent: Color(0xFF38BDF8),
      onAccent: Color(0xFF082F49),
      dirty: Color(0xFFF5B545),
      attention: Color(0xFFF2637A),
      onAttention: Color(0xFF08222F),
    ),
    light: AppearanceContentSeed(
      primary: Color(0xFF087DA5),
      onPrimary: Color(0xFFFFFFFF),
      surfaceTint: Color(0xFF1295C7),
    ),
    dark: AppearanceContentSeed(
      primary: Color(0xFF38BDF8),
      onPrimary: Color(0xFF082F49),
      surfaceTint: Color(0xFF1295C7),
    ),
  );

  static const List<AppearancePreset> all = [
    vinabike,
    midnight,
    aubergine,
    graphite,
    evergreen,
    pacific,
  ];

  static const List<SidebarPaletteOption> sidebarPalettes = [
    vinabikeSidebar,
    midnightSidebar,
    aubergineSidebar,
    graphiteSidebar,
    evergreenSidebar,
    pacificSidebar,
  ];

  static AppearancePreset byCode(String code) {
    return maybeByCode(code) ?? vinabike;
  }

  static AppearancePreset? maybeByCode(String code) {
    for (final preset in all) {
      if (preset.code == code) return preset;
    }
    return null;
  }
}
