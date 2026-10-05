import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';

export 'package:vinabike_public_core/modules/website/models/website_block_type.dart';

/// The editor's icon for each block type; the type itself lives in the shared
/// core, which the HTML storefront also compiles.
extension WebsiteBlockTypeIcon on WebsiteBlockType {
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
