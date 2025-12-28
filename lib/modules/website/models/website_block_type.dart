import 'package:flutter/material.dart';

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

  IconData get icon => switch (this) {
        WebsiteBlockType.hero => Icons.view_carousel,
        WebsiteBlockType.carousel => Icons.slideshow,
        WebsiteBlockType.canvas => Icons.dashboard_customize_outlined,
        WebsiteBlockType.text => Icons.text_fields,
        WebsiteBlockType.button => Icons.smart_button,
        WebsiteBlockType.divider => Icons.horizontal_rule,
        WebsiteBlockType.products => Icons.shopping_bag,
        WebsiteBlockType.services => Icons.room_service,
        WebsiteBlockType.about => Icons.info_outline,
        WebsiteBlockType.testimonials => Icons.format_quote,
        WebsiteBlockType.features => Icons.star_outline,
        WebsiteBlockType.cta => Icons.touch_app,
        WebsiteBlockType.gallery => Icons.photo_library_outlined,
        WebsiteBlockType.contact => Icons.mail_outline,
        WebsiteBlockType.faq => Icons.help_outline,
        WebsiteBlockType.pricing => Icons.price_change,
        WebsiteBlockType.team => Icons.groups,
        WebsiteBlockType.stats => Icons.insights,
        WebsiteBlockType.footer => Icons.web_asset,
        WebsiteBlockType.categoryGrid => Icons.grid_view_rounded,
        WebsiteBlockType.videoBanner => Icons.play_circle_outline,
        WebsiteBlockType.partnersBanner => Icons.handshake_outlined,
        WebsiteBlockType.brandLogos => Icons.branding_watermark,
        WebsiteBlockType.googleReviews => Icons.reviews,
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
