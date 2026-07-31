part of '../public_store_layout.dart';

/// Geometry contract for the shared storefront header.
///
/// Compact widths reserve three canonical 48 px touch targets before sizing
/// the wordmark. Keeping this arithmetic in one policy makes the 320 px floor
/// testable without coupling a regression to network image timing.
class PublicStoreHeaderGeometry {
  const PublicStoreHeaderGeometry({
    required this.isDesktop,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.logoHeight,
    required this.logoMaxWidth,
    required this.logoHitBox,
    required this.logoGap,
    required this.iconSize,
    required this.iconBox,
    required this.actionGap,
  });

  factory PublicStoreHeaderGeometry.resolve(double width) {
    final isDesktop = width >= 1080;
    final isNarrowCompact = !isDesktop && width < 360;
    return PublicStoreHeaderGeometry(
      isDesktop: isDesktop,
      horizontalPadding: isDesktop ? 24 : (isNarrowCompact ? 12 : 16),
      verticalPadding: isDesktop ? 8 : (isNarrowCompact ? 8 : 10),
      logoHeight: isDesktop ? 38 : (isNarrowCompact ? 34 : 40),
      // Desktop retains the authored wordmark behavior. The cap exists only
      // where the compact row must reserve three 48 px actions.
      logoMaxWidth: isDesktop ? null : (isNarrowCompact ? 110 : 140),
      logoHitBox: isDesktop ? 40 : 48,
      logoGap: isDesktop ? 22 : (isNarrowCompact ? 8 : 16),
      iconSize: isDesktop ? 22 : 23,
      iconBox: isDesktop ? 40 : 48,
      actionGap: isDesktop ? 2 : 4,
    );
  }

  final bool isDesktop;
  final double horizontalPadding;
  final double verticalPadding;
  final double logoHeight;
  final double? logoMaxWidth;
  final double logoHitBox;
  final double logoGap;
  final double iconSize;
  final double iconBox;
  final double actionGap;

  double get compactRequiredWidth =>
      horizontalPadding * 2 +
      (logoMaxWidth ?? 0) +
      logoGap +
      iconBox * 3 +
      actionGap * 2;
}
