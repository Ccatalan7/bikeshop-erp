import 'package:flutter/material.dart';

/// Shared contrast policy for the public storefront header.
///
/// Automatic mode follows the surface beneath a solid header and uses the
/// protected light-foreground treatment whenever the header overlays page
/// content. Explicit light/dark modes remain available as deliberate editor
/// overrides.
enum PublicHeaderContrastMode { automatic, light, dark }

extension PublicHeaderContrastModeX on PublicHeaderContrastMode {
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
        return isOverlay || backgroundColor.computeLuminance() < 0.42;
    }
  }
}
