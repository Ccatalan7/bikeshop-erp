import 'package:flutter/material.dart';

/// Shared contrast policy for the public storefront header.
///
/// Automatic mode follows the surface beneath a solid header and uses the
/// protected light-foreground treatment whenever the header overlays page
/// content. Explicit light/dark modes remain available as deliberate editor
/// overrides.
enum PublicHeaderContrastMode { automatic, light, dark }

extension PublicHeaderContrastModeX on PublicHeaderContrastMode {
  static double _contrastRatio(Color a, Color b) {
    final aLuminance = a.computeLuminance();
    final bLuminance = b.computeLuminance();
    final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
    final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static PublicHeaderContrastMode parse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'light':
        return PublicHeaderContrastMode.light;
      case 'dark':
        return PublicHeaderContrastMode.dark;
      case 'auto':
      case 'automatic':
      default:
        return PublicHeaderContrastMode.automatic;
    }
  }

  bool usesLightForeground({
    required bool isOverlay,
    required Color backgroundColor,
  }) {
    switch (this) {
      case PublicHeaderContrastMode.light:
        return false;
      case PublicHeaderContrastMode.dark:
        return true;
      case PublicHeaderContrastMode.automatic:
        if (isOverlay) return true;
        return _contrastRatio(Colors.white, backgroundColor) >=
            _contrastRatio(const Color(0xFF17211B), backgroundColor);
    }
  }
}
