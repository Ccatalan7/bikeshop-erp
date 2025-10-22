import 'package:flutter/material.dart';

/// Canonical set of supported website block types for the visual editor
/// and the public storefront renderer. Serialized name is always the enum's
/// Dart name (e.g. `hero`, `pricing`, `faq`).
enum WebsiteBlockType {
  hero,
  carousel,
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
}

extension WebsiteBlockTypeX on WebsiteBlockType {
  String get serialized => name;

  IconData get icon => switch (this) {
        WebsiteBlockType.hero => Icons.view_carousel,
        WebsiteBlockType.carousel => Icons.slideshow,
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
      };
}

WebsiteBlockType parseWebsiteBlockType(
  String raw, {
  WebsiteBlockType fallback = WebsiteBlockType.hero,
}) {
  final normalised = raw.toLowerCase().trim();
  for (final value in WebsiteBlockType.values) {
    if (value.name == normalised) {
      return value;
    }
  }
  return fallback;
}
