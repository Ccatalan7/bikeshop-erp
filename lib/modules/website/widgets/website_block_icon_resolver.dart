import 'package:flutter/material.dart';

/// Pure mapping from Website Builder persisted icon names to Material icons.
///
/// Definitions keep owning which values editors may write. Shared content
/// widgets consume this resolver so Edit, Preview and Public cannot disagree
/// about the icon painted for the same value.
abstract final class WebsiteBlockIconResolver {
  static IconData resolve(String? rawName) {
    return switch (rawName?.trim().toLowerCase()) {
      'directions_bike' => Icons.directions_bike,
      'build' => Icons.build,
      'tune' => Icons.tune,
      'shopping_bag' => Icons.shopping_bag,
      'verified' => Icons.verified,
      'pedal_bike' => Icons.pedal_bike,
      'support_agent' => Icons.support_agent,
      'favorite' => Icons.favorite,
      'star' => Icons.star,
      'local_shipping' => Icons.local_shipping,
      'check_circle' => Icons.check_circle,
      'links' => Icons.link,
      'instagram' => Icons.camera_alt_outlined,
      'strava' => Icons.timeline,
      'facebook' => Icons.thumb_up_alt_outlined,
      'phone' => Icons.phone,
      'mail' => Icons.mail_outline,
      'location' => Icons.location_on_outlined,
      _ => Icons.star,
    };
  }
}
