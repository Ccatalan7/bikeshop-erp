import '../../modules/website/theme/website_theme_color_value.dart';
import '../../modules/website/theme/website_theme_roles.dart';
import 'public_header_contrast.dart';

/// The open wide menu's colors, one rule for the HTML store and the Flutter
/// canvas (2026-10-25, the menu with a column of sections).
///
/// The editor keeps two colors under «Menú desplegado»: the panel
/// (`header_menu_surface_color`) and its column of sections
/// (`header_menu_rail_color`). Blank or transparent, the panel is the theme's
/// background and the column a breath darker than it; any other value is
/// drawn opaque. Words take white or the theme's text by the header's
/// contrast rule, and the store's color marks links and the open section
/// wherever it reads on the panel (4.5 : 1), else the text color does.
class HeaderMenuPalette {
  const HeaderMenuPalette._({
    required this.surface,
    required this.onSurface,
    required this.muted,
    required this.ink,
    required this.divider,
    required this.helpFill,
    required this.rail,
    required this.onRail,
    required this.railHover,
    required this.railActive,
    required this.onRailActive,
    required this.surfaceLight,
  });

  static const surfaceKey = 'header_menu_surface_color';
  static const railKey = 'header_menu_rail_color';

  /// [read] returns the setting as saved, or '' when there is none.
  factory HeaderMenuPalette.resolve(
    WebsiteThemeRoles roles,
    String Function(String key) read,
  ) => HeaderMenuPalette.fromTheme(
    primary: roles.primary,
    background: roles.background,
    onSurface: roles.onSurface,
    read: read,
  );

  /// The same rule from the theme's three colors, as the Flutter canvas
  /// holds them (`ColorScheme.primary`, `surface`, `onSurface`).
  factory HeaderMenuPalette.fromTheme({
    required WebsiteRgba primary,
    required WebsiteRgba background,
    required WebsiteRgba onSurface,
    required String Function(String key) read,
  }) {
    final themeText = onSurface;
    WebsiteRgba? configured(String key) {
      final argb = parseWebsiteThemeColorValue(read(key));
      if (argb == null || ((argb >> 24) & 0xFF) / 255 <= 0.01) return null;
      return WebsiteRgba.fromArgb(0xFF000000 | (argb & 0xFFFFFF));
    }

    bool light(WebsiteRgba color) => PublicHeaderContrastMode.automatic
        .usesLightForegroundOn(isOverlay: false, backgroundArgb: _argb(color));

    final ownSurface = configured(surfaceKey);
    final surface = ownSurface ?? background.withAlpha(1);
    final surfaceLight = light(surface);
    final panelText = ownSurface == null
        ? themeText
        : surfaceLight
        ? WebsiteRgba.white
        : themeText;
    final brandReads = WebsiteRgba.contrast(primary, surface) >= 4.5;
    final ink = brandReads ? primary : panelText;

    final ownRail = configured(railKey);
    final rail = ownRail ?? WebsiteRgba.lerp(surface, panelText, 0.025);
    final onRail = ownRail == null
        ? panelText
        : light(rail)
        ? WebsiteRgba.white
        : themeText;
    final railActive = brandReads && ownRail == null
        ? WebsiteRgba.alphaBlend(primary.withAlpha(0.11), rail)
        : WebsiteRgba.lerp(rail, onRail, 0.12);
    return HeaderMenuPalette._(
      surface: surface,
      onSurface: panelText,
      muted: WebsiteRgba.lerp(panelText, surface, 0.3),
      ink: ink,
      divider: WebsiteRgba.lerp(surface, panelText, 0.1),
      helpFill: WebsiteRgba.lerp(surface, panelText, 0.04),
      rail: rail,
      onRail: onRail,
      railHover: WebsiteRgba.lerp(rail, onRail, 0.06),
      railActive: railActive,
      onRailActive: WebsiteRgba.contrast(ink, railActive) >= 4.5 ? ink : onRail,
      surfaceLight: surfaceLight,
    );
  }

  static int _argb(WebsiteRgba c) {
    int channel(double v) => (v * 255).round() & 0xFF;
    return channel(c.a) << 24 |
        channel(c.r) << 16 |
        channel(c.g) << 8 |
        channel(c.b);
  }

  /// The panel, and the header over it while the menu is open.
  final WebsiteRgba surface;

  /// A section's title and its subcategories' names.
  final WebsiteRgba onSurface;

  /// The third level's links and the help card's words.
  final WebsiteRgba muted;

  /// «Ver todo …», the icons and the help card's link.
  final WebsiteRgba ink;

  /// The column's edge and the rule above «Ver todo».
  final WebsiteRgba divider;
  final WebsiteRgba helpFill;

  /// The column of sections and its rows.
  final WebsiteRgba rail;
  final WebsiteRgba onRail;
  final WebsiteRgba railHover;
  final WebsiteRgba railActive;
  final WebsiteRgba onRailActive;

  /// White words on the panel, header included.
  final bool surfaceLight;
}
