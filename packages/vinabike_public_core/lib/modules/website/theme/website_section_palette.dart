import '../models/website_section_tone.dart';
import 'website_theme_roles.dart';

export '../models/website_section_tone.dart';

/// The colors a section block draws with, from the site theme's primary,
/// accent, background and text colors. Pure Dart: the Flutter canvas and the
/// HTML storefront mix the very same channels, so a section looks the same in
/// the editor and on the site, whatever brand colors the store has.
///
/// The dark tones are the primary color taken toward black; the light band
/// and the rules are the background with a little of the primary in it; text
/// on a dark tone is white, or the store's dark ink when the primary is so
/// light that white would not read.
class WebsiteSectionPalette {
  const WebsiteSectionPalette._({
    required this.tone,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.strongRule,
    required this.eyebrow,
    required this.mark,
    required this.tint,
    required this.card,
    required this.cardRule,
    required this.accent,
    required this.onAccent,
  });

  /// [tone]'s colors for a theme with these four colors.
  factory WebsiteSectionPalette.resolve({
    required WebsiteSectionTone tone,
    required WebsiteRgba primary,
    required WebsiteRgba accent,
    required WebsiteRgba background,
    required WebsiteRgba onSurface,
  }) {
    final tones = WebsiteSectionTones.derive(
      primary: primary,
      accent: accent,
      background: background,
    );
    final onAccent = WebsiteRgba.readableOn(accent);
    if (tone == WebsiteSectionTone.dark) {
      final ink = WebsiteRgba.readableOn(tones.deep);
      final lightInk = ink.luminance > 0.5;
      return WebsiteSectionPalette._(
        tone: tone,
        surface: tones.deep,
        ink: ink,
        muted: ink.withAlpha(0.72),
        rule: ink.withAlpha(0.18),
        strongRule: ink.withAlpha(0.56),
        eyebrow: lightInk ? tones.accentOnDark : ink,
        mark: lightInk ? tones.accentOnDark : ink,
        tint: ink.withAlpha(0.1),
        card: WebsiteRgba.lerp(tones.deep, ink, 0.06),
        cardRule: ink.withAlpha(0.18),
        accent: accent,
        onAccent: onAccent,
      );
    }
    final surface = tone == WebsiteSectionTone.band ? tones.band : background;
    final primaryInk = _firstReadable([
      primary,
      tones.deep,
      onSurface,
    ], on: surface);
    return WebsiteSectionPalette._(
      tone: tone,
      surface: surface,
      ink: onSurface,
      muted: WebsiteRgba.lerp(onSurface, surface, 0.3),
      rule: tones.rule,
      strongRule: onSurface,
      eyebrow: primaryInk,
      mark: primaryInk,
      tint: tones.tint,
      card: background,
      cardRule: tones.rule,
      accent: accent,
      onAccent: onAccent,
    );
  }

  final WebsiteSectionTone tone;

  /// The section's background.
  final WebsiteRgba surface;

  /// Titles, names, prices and questions.
  final WebsiteRgba ink;

  /// Notes, details, labels and answers.
  final WebsiteRgba muted;

  /// The hairline between rows and around cards.
  final WebsiteRgba rule;

  /// The heavier line that closes a section's header (2 px).
  final WebsiteRgba strongRule;

  /// The small capitals above a title.
  final WebsiteRgba eyebrow;

  /// Checks, links and the initials of a quote: the brand on light tones, the
  /// lightened accent on dark ones.
  final WebsiteRgba mark;

  /// The circle behind an initial or a portrait.
  final WebsiteRgba tint;

  /// A card lifted from the section (a plan).
  final WebsiteRgba card;
  final WebsiteRgba cardRule;

  /// The site's accent, for the one action a section leads to.
  final WebsiteRgba accent;
  final WebsiteRgba onAccent;

  bool get isDark => tone == WebsiteSectionTone.dark;

  static WebsiteRgba _firstReadable(
    List<WebsiteRgba> candidates, {
    required WebsiteRgba on,
  }) {
    for (final candidate in candidates) {
      if (WebsiteRgba.contrast(candidate, on) >= 4.5) return candidate;
    }
    return candidates.last;
  }
}

/// The tones a theme's section blocks share: [deep] (a dark band, the
/// featured plan, the address tile), [deeper] (the brands strip and the veil
/// over a call to action's photo), [band] (the light band), [rule] and
/// [tint], and [accentOnDark], the accent lightened to read on the dark
/// tones.
class WebsiteSectionTones {
  const WebsiteSectionTones._({
    required this.deep,
    required this.deeper,
    required this.band,
    required this.rule,
    required this.tint,
    required this.accentOnDark,
  });

  factory WebsiteSectionTones.derive({
    required WebsiteRgba primary,
    required WebsiteRgba accent,
    required WebsiteRgba background,
  }) {
    const black = WebsiteRgba(1, 0, 0, 0);
    final opaquePrimary = primary.withAlpha(1);
    final opaqueBackground = background.withAlpha(1);
    return WebsiteSectionTones._(
      deep: WebsiteRgba.lerp(opaquePrimary, black, 0.34),
      deeper: WebsiteRgba.lerp(opaquePrimary, black, 0.5),
      band: WebsiteRgba.lerp(opaqueBackground, opaquePrimary, 0.05),
      rule: WebsiteRgba.lerp(opaqueBackground, opaquePrimary, 0.15),
      tint: WebsiteRgba.lerp(opaqueBackground, opaquePrimary, 0.1),
      accentOnDark: WebsiteRgba.lerp(
        accent.withAlpha(1),
        WebsiteRgba.white,
        0.3,
      ),
    );
  }

  final WebsiteRgba deep;
  final WebsiteRgba deeper;
  final WebsiteRgba band;
  final WebsiteRgba rule;
  final WebsiteRgba tint;
  final WebsiteRgba accentOnDark;
}

/// How wide a section block is drawn, by the width it has (not the window's):
/// a phone under 600, a tablet up to 1023, a desktop from 1024. Both
/// renderers lay a section out by these bands (the HTML with container
/// queries on the block), and [WebsiteSectionMetrics] gives each its sizes.
enum WebsiteSectionWidth {
  phone,
  tablet,
  desktop;

  static const tabletFrom = 600.0;
  static const desktopFrom = 1024.0;

  static WebsiteSectionWidth of(double width) => width >= desktopFrom
      ? desktop
      : width >= tabletFrom
      ? tablet
      : phone;
}

/// The sizes a section block shares at each [WebsiteSectionWidth]: its
/// padding, the column its content keeps to, and its header's type.
class WebsiteSectionMetrics {
  const WebsiteSectionMetrics._({
    required this.width,
    required this.paddingBlock,
    required this.paddingInline,
    required this.titleSize,
    required this.noteSize,
    required this.eyebrowSize,
    required this.headerGap,
  });

  factory WebsiteSectionMetrics.of(WebsiteSectionWidth width) =>
      switch (width) {
        WebsiteSectionWidth.desktop => const WebsiteSectionMetrics._(
          width: WebsiteSectionWidth.desktop,
          paddingBlock: 112,
          paddingInline: 32,
          titleSize: 48,
          noteSize: 17,
          eyebrowSize: 13,
          headerGap: 48,
        ),
        WebsiteSectionWidth.tablet => const WebsiteSectionMetrics._(
          width: WebsiteSectionWidth.tablet,
          paddingBlock: 88,
          paddingInline: 32,
          titleSize: 42,
          noteSize: 17,
          eyebrowSize: 13,
          headerGap: 40,
        ),
        WebsiteSectionWidth.phone => const WebsiteSectionMetrics._(
          width: WebsiteSectionWidth.phone,
          paddingBlock: 64,
          paddingInline: 20,
          titleSize: 36,
          noteSize: 16,
          eyebrowSize: 12,
          headerGap: 28,
        ),
      };

  /// The widest a section's content runs (the design's 1200 less its 32 px
  /// sides).
  static const contentMaxWidth = 1136.0;

  final WebsiteSectionWidth width;
  final double paddingBlock;
  final double paddingInline;

  /// The section's title: the heading font, uppercase, 1.05 line.
  final double titleSize;

  /// The note beside (or under) the title.
  final double noteSize;

  /// The small capitals above the title (0.18 em tracking).
  final double eyebrowSize;

  /// Between the header and the section's content.
  final double headerGap;

  bool get isPhone => width == WebsiteSectionWidth.phone;
  bool get isDesktop => width == WebsiteSectionWidth.desktop;
}
