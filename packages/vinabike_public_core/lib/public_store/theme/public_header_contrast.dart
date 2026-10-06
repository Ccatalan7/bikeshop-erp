import '../../modules/website/theme/website_theme_roles.dart';

/// Shared contrast policy for the public storefront header.
///
/// Automatic mode follows the surface beneath a solid header and uses the
/// protected light-foreground treatment whenever the header overlays page
/// content. Explicit light/dark modes remain available as deliberate editor
/// overrides.
///
/// Pure Dart, colors as ARGB integers: the Flutter header and the HTML
/// store's header and wide menu decide white or dark words with this one
/// rule (the Flutter extension adapts `Color`).
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

  bool usesLightForegroundOn({
    required bool isOverlay,
    required int backgroundArgb,
  }) {
    switch (this) {
      case PublicHeaderContrastMode.light:
        return false;
      case PublicHeaderContrastMode.dark:
        return true;
      case PublicHeaderContrastMode.automatic:
        if (isOverlay) return true;
        return _contrastRatio(0xFFFFFFFF, backgroundArgb) >=
            _contrastRatio(0xFF17211B, backgroundArgb);
    }
  }
}

double _contrastRatio(int a, int b) {
  final aLuminance = WebsiteRgba.fromArgb(a).luminance;
  final bLuminance = WebsiteRgba.fromArgb(b).luminance;
  final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
  final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
