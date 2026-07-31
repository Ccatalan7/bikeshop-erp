import 'package:flutter/material.dart';

/// One persisted appearance preset at the palette boundary.
///
/// The values remain migration input while `WorkspaceChromeTheme` turns them
/// into complete semantic and component roles. Feature code must not consume
/// these literal palette fields directly.
class SidebarPaletteOption {
  const SidebarPaletteOption({
    required this.code,
    required this.name,
    required this.description,
    required this.background,
    required this.backgroundAlt,
    required this.foreground,
    required this.mutedForeground,
    required this.accent,
    required this.onAccent,
    required this.border,
  });

  final String code;
  final String name;
  final String description;
  final Color background;
  final Color backgroundAlt;
  final Color foreground;
  final Color mutedForeground;
  final Color accent;
  final Color onAccent;
  final Color border;
}
