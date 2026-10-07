import 'website_block_type.dart';

/// The background a section block is drawn on (the editor's «Fondo de la
/// sección» of stats, services, plans, testimonials, gallery, team and
/// questions): the site's own background, a light band of the brand color, or
/// a dark one. Two sections in a row on different tones read as two chapters
/// of the page, as a store theme's sections do in Shopify («color scheme»).
enum WebsiteSectionTone {
  light,
  band,
  dark;

  /// The stored value (`tone`), or [fallback] when it is absent or unknown.
  static WebsiteSectionTone fromStorage(
    Object? raw, {
    required WebsiteSectionTone fallback,
  }) {
    final value = raw?.toString().trim().toLowerCase();
    for (final tone in values) {
      if (tone.name == value) return tone;
    }
    return fallback;
  }

  /// [data]'s background: its `tone`, or [type]'s default.
  static WebsiteSectionTone of(
    WebsiteBlockType type,
    Map<String, dynamic> data,
  ) => fromStorage(
    data['tone'],
    fallback: websiteSectionDefaultTone(type) ?? WebsiteSectionTone.light,
  );
}

/// The background a section block has when it says none (`tone`): the
/// default of its «Fondo de la sección», `null` for a block that is not a
/// section.
WebsiteSectionTone? websiteSectionDefaultTone(WebsiteBlockType? type) =>
    switch (type) {
      WebsiteBlockType.stats => WebsiteSectionTone.dark,
      WebsiteBlockType.services ||
      WebsiteBlockType.testimonials ||
      WebsiteBlockType.team => WebsiteSectionTone.light,
      WebsiteBlockType.pricing ||
      WebsiteBlockType.gallery ||
      WebsiteBlockType.faq => WebsiteSectionTone.band,
      _ => null,
    };

/// The section blocks of the sections design (2026-10-07): bands that paint
/// their own background from edge to edge and keep the page's rhythm in their
/// own padding, so two of them in a row meet without the page's gap between
/// them (`WebsitePageComposition`).
const websiteSectionBandTypes = <WebsiteBlockType>{
  WebsiteBlockType.stats,
  WebsiteBlockType.services,
  WebsiteBlockType.pricing,
  WebsiteBlockType.testimonials,
  WebsiteBlockType.gallery,
  WebsiteBlockType.team,
  WebsiteBlockType.faq,
  WebsiteBlockType.partnersBanner,
  WebsiteBlockType.cta,
};
