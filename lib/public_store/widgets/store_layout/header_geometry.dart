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

  /// [menuFits]: the whole desktop menu fits beside the logo and the tools
  /// (2026-11-21, as the HTML store's `menu-compact`). A longer menu makes
  /// the bar compact, as on a phone, instead of running under the tools.
  factory PublicStoreHeaderGeometry.resolve(
    double width, {
    bool menuFits = true,
  }) {
    final isDesktop = width >= 1080 && menuFits;
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

/// Lays the desktop menu out at the width it needs and reports it with the
/// width the bar leaves it (2026-11-21), so the header can turn compact when
/// the menu does not fit. Paints like the row it holds, from the start.
class _HeaderMenuProbe extends SingleChildRenderObjectWidget {
  const _HeaderMenuProbe({required this.onMeasured, super.child});

  final void Function(double needed, double available) onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeaderMenuProbe(onMeasured);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeaderMenuProbe renderObject,
  ) {
    renderObject.onMeasured = onMeasured;
  }
}

class _RenderHeaderMenuProbe extends RenderProxyBox {
  _RenderHeaderMenuProbe(this.onMeasured);

  void Function(double needed, double available) onMeasured;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      BoxConstraints(
        minHeight: constraints.minHeight,
        maxHeight: constraints.maxHeight,
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(child.size);
    final needed = child.size.width;
    final available = constraints.maxWidth;
    final report = onMeasured;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => report(needed, available),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (child.size.width <= size.width) {
      context.paintChild(child, offset);
      return;
    }
    // A frame before the header turns compact: never over the tools.
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => context.paintChild(child, offset),
    );
  }
}
