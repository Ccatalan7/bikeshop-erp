/// Canonical set of supported website block types for the visual editor
/// and the public storefront renderer. Serialized name is always the enum's
/// Dart name (e.g. `hero`, `pricing`, `faq`).
enum WebsiteBlockType {
  hero,
  carousel,

  /// Free-position canvas section (Wix-like)
  canvas,

  /// Simple text element (freeform text section)
  text,

  /// Button element (CTA button with link)
  button,

  /// Horizontal divider/separator
  divider,
  products,
  services,
  about,
  testimonials,
  features,
  cta,
  gallery,
  contact,
  faq,
  pricing,
  team,
  stats,
  footer,
  // New modern blocks
  categoryGrid, // Large image cards for categories (MTB, Road, Kids, etc.)
  videoBanner, // Full-width video/image banner section
  partnersBanner, // Dark banner with text list (partners, locations)
  brandLogos, // Brand logos carousel/grid (like Commencal's accessory brands)
  googleReviews, // Google Reviews Carousel
}

extension WebsiteBlockTypeX on WebsiteBlockType {
  String get serialized => name;

  String get editorCategory => switch (this) {
        WebsiteBlockType.hero ||
        WebsiteBlockType.carousel ||
        WebsiteBlockType.categoryGrid ||
        WebsiteBlockType.canvas =>
          'Estructura',
        WebsiteBlockType.text ||
        WebsiteBlockType.button ||
        WebsiteBlockType.divider =>
          'Elementos',
        WebsiteBlockType.products ||
        WebsiteBlockType.about ||
        WebsiteBlockType.services ||
        WebsiteBlockType.features =>
          'Contenido',
        WebsiteBlockType.gallery ||
        WebsiteBlockType.videoBanner ||
        WebsiteBlockType.brandLogos ||
        WebsiteBlockType.partnersBanner =>
          'Media',
        WebsiteBlockType.testimonials ||
        WebsiteBlockType.googleReviews ||
        WebsiteBlockType.team ||
        WebsiteBlockType.stats =>
          'Social',
        WebsiteBlockType.cta ||
        WebsiteBlockType.pricing ||
        WebsiteBlockType.contact ||
        WebsiteBlockType.faq =>
          'Conversión',
        WebsiteBlockType.footer => 'Especial',
      };
}

WebsiteBlockType parseWebsiteBlockType(
  String raw, {
  WebsiteBlockType fallback = WebsiteBlockType.hero,
}) {
  final normalised = raw.trim();
  for (final value in WebsiteBlockType.values) {
    // Case-insensitive comparison to handle both "categoryGrid" and "categorygrid"
    if (value.name.toLowerCase() == normalised.toLowerCase()) {
      return value;
    }
  }
  return fallback;
}
