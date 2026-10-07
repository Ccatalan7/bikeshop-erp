import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';

import '../models/website_action.dart';
import 'website_block_content_presenters.dart';
import 'website_section_frame.dart';

/// Shared visitor content for the schema-defined Pricing collection: the
/// header, then the plans side by side in one card (the highlighted one on
/// the dark tone, with its badge and the accent button), or as stacked cards
/// when each would have less than 260 (`websitePlansSideBySide`); stacked,
/// only the highlighted plan keeps its button. The HTML storefront draws the
/// same (`PricingSectionView`).
///
/// Public, Preview and Edit use one tree. Edit replaces only typed text and
/// action leaves; structural collection operations remain inspector-owned.
class WebsitePricingBlockContent extends StatelessWidget {
  const WebsitePricingBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    this.previewMode = false,
    this.onNavigate,
    this.isNavigationEligible,
    this.presenters,
    this.padding,
    this.paintSurface = true,
  });

  static const rootKey = ValueKey<String>('website-pricing-content-root');
  static const collectionKey = ValueKey<String>('website-pricing-collection');

  static ValueKey<String> planKey(int index) =>
      ValueKey<String>('website-pricing-plan-$index');

  static ValueKey<String> actionKey(int index) =>
      ValueKey<String>('website-pricing-action-$index');

  static ValueKey<String> priceKey(int index) =>
      ValueKey<String>('website-pricing-price-$index');

  static const _collection = <String>['plans', 'items'];

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final WebsiteBlockContentPresenters? presenters;

  /// The padding the operator set; `null` keeps the design's.
  final EdgeInsetsGeometry? padding;
  final bool paintSurface;

  @override
  Widget build(BuildContext context) {
    final plans = websiteSectionItems(data, 'plans', const ['items']);
    return KeyedSubtree(
      key: rootKey,
      child: WebsiteSectionBand(
        tone: WebsiteSectionTone.of(WebsiteBlockType.pricing, data),
        primaryColor: primaryColor,
        accentColor: accentColor,
        headingFont: headingFont,
        bodyFont: bodyFont,
        padding: padding,
        paintSurface: paintSurface,
        builder: (context, scope) {
          final header = WebsiteSectionHeader(
            scope: scope,
            data: data,
            idPrefix: 'pricing',
            presenters: presenters,
          );
          final sideBySide = websitePlansSideBySide(
            plans.length,
            scope.contentWidth,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!header.isEmpty) header,
              if (plans.isNotEmpty) ...[
                if (!header.isEmpty) SizedBox(height: scope.isPhone ? 28 : 48),
                sideBySide
                    ? _sideBySide(context, scope, plans)
                    : _stacked(context, scope, plans),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sideBySide(
    BuildContext context,
    WebsiteSectionScope scope,
    List<(int, Map<String, dynamic>)> plans,
  ) {
    final colors = scope.colors;
    return Container(
      key: collectionKey,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.card,
        border: Border.all(color: colors.cardRule),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (position, (index, plan)) in plans.indexed)
              Expanded(
                child: _Plan(
                  key: planKey(index),
                  owner: this,
                  plan: plan,
                  index: index,
                  scope: scope,
                  stacked: false,
                  last: position == plans.length - 1,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stacked(
    BuildContext context,
    WebsiteSectionScope scope,
    List<(int, Map<String, dynamic>)> plans,
  ) {
    return Column(
      key: collectionKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (position, (index, plan)) in plans.indexed) ...[
          if (position > 0) const SizedBox(height: 12),
          _Plan(
            key: planKey(index),
            owner: this,
            plan: plan,
            index: index,
            scope: scope,
            stacked: true,
            last: position == plans.length - 1,
          ),
        ],
      ],
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({
    super.key,
    required this.owner,
    required this.plan,
    required this.index,
    required this.scope,
    required this.stacked,
    required this.last,
  });

  final WebsitePricingBlockContent owner;
  final Map<String, dynamic> plan;
  final int index;
  final WebsiteSectionScope scope;
  final bool stacked;
  final bool last;

  WebsiteBlockContentPresenters? get presenters => owner.presenters;

  @override
  Widget build(BuildContext context) {
    final featured = plan['highlighted'] == true || plan['isFeatured'] == true;
    final colors = featured ? scope.inverse : scope.colors;
    final featuredScope = WebsiteSectionScope(
      metrics: scope.metrics,
      colors: colors,
      inverse: scope.inverse,
      contentWidth: scope.contentWidth,
      headingFont: scope.headingFont,
      bodyFont: scope.bodyFont,
    );
    final s = featuredScope;
    final target = websiteSectionTarget(
      plan,
      index: index,
      collectionKeys: WebsitePricingBlockContent._collection,
    );
    final name = websiteSectionText(plan, const ['name']);
    final tag = websiteSectionText(plan, const ['tag']).trim();
    final badge = websiteSectionText(plan, const ['badge']).trim();
    final price = websiteSectionText(plan, const ['price']);
    final note = websiteSectionText(plan, const ['note']).trim();
    final features = [
      if (plan['features'] case final List raw)
        for (final feature in raw)
          if (feature.toString().trim().isNotEmpty) feature.toString().trim(),
    ];
    final action = WebsiteActionValue.resolvePrimary(
      plan,
      labelKeys: const <String>['ctaText', 'buttonText'],
      hrefKeys: const <String>['ctaLink', 'buttonLink'],
      variantKeys: const <String>['actionVariant'],
      defaultLabel: '',
    );
    final href = action?.href.trim() ?? '';
    final showAction = action != null &&
        action.label.trim().isNotEmpty &&
        href.isNotEmpty &&
        (owner.isNavigationEligible?.call(href) ?? true) &&
        (!stacked || featured);
    final nameSlot = websiteSectionSlot(
      context,
      presenters,
      WebsiteInlineTextSlot(
        id: 'pricing.plan.$index.name',
        value: name,
        valueKeys: const <String>['name'],
        baseStyle: s.heading(stacked ? 24 : 30, height: 1.2),
        formatting: websiteSectionFormatting(plan['nameFormatting']),
        formattingKeys: const <String>['nameFormatting'],
        placeholder: 'Nombre del plan',
        displayTransform: (value) => value.toUpperCase(),
        repeaterTarget: target,
      ),
    );
    Widget priceSlot(double size, {double height = 1}) => websiteSectionSlot(
          context,
          presenters,
          WebsiteInlineTextSlot(
            id: 'pricing.plan.$index.price',
            value: price,
            valueKeys: const <String>['price'],
            baseStyle: s.heading(size, height: height),
            formatting: websiteSectionFormatting(plan['priceFormatting']),
            formattingKeys: const <String>['priceFormatting'],
            placeholder: r'$0',
            displayTransform: (value) => value.trim(),
            repeaterTarget: target,
          ),
          key: WebsitePricingBlockContent.priceKey(index),
        );
    final badgeWidget = featured && badge.isNotEmpty
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: colors.accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: stacked
                  ? const EdgeInsets.symmetric(horizontal: 9, vertical: 5)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                badge.toUpperCase(),
                style: s.caps(
                  stacked ? 11 : 12,
                  tracking: 0.12,
                  weight: FontWeight.w700,
                  color: colors.onAccent,
                ),
              ),
            ),
          )
        : null;
    final featureList = features.isEmpty
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (position, feature) in features.indexed) ...[
                if (position > 0) SizedBox(height: stacked ? 10 : 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: stacked ? 2 : 1),
                      child: Icon(
                        Icons.check,
                        size: stacked ? 18 : 20,
                        color: colors.mark,
                      ),
                    ),
                    SizedBox(width: stacked ? 10 : 12),
                    Expanded(
                      child: Text(
                        feature,
                        style: s.body(stacked ? 15 : 16, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
    final button = showAction
        ? KeyedSubtree(
            key: WebsitePricingBlockContent.actionKey(index),
            child: websiteSectionAction(
              context,
              presenters: presenters,
              id: 'pricing.plan.$index.action',
              action: action,
              labelKeys: const <String>['ctaText', 'buttonText'],
              hrefKeys: const <String>['ctaLink', 'buttonLink'],
              variantKeys: const <String>['actionVariant'],
              kind: featured
                  ? WebsiteSectionButtonKind.accent
                  : WebsiteSectionButtonKind.line,
              colors: colors,
              onNavigate: owner.onNavigate,
              repeaterTarget: target,
              bodyFont: s.bodyFont,
              expand: true,
            ),
          )
        : null;

    if (stacked) {
      return Container(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        decoration: BoxDecoration(
          color: featured ? colors.surface : colors.card,
          border: featured ? null : Border.all(color: colors.cardRule),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (badgeWidget != null) ...[
              Align(alignment: Alignment.centerLeft, child: badgeWidget),
              const SizedBox(height: 14),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: nameSlot),
                if (price.trim().isNotEmpty) ...[
                  const SizedBox(width: 12),
                  priceSlot(32, height: 1.2),
                ],
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(note, style: s.body(14, height: 1.45, color: colors.muted)),
            ],
            if (featureList != null) ...[
              const SizedBox(height: 16),
              featureList,
            ],
            if (button != null) ...[
              const SizedBox(height: 22),
              button,
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(36, 40, 36, 40),
      decoration: BoxDecoration(
        color: featured ? colors.surface : colors.card,
        border: Border(
          right: last ? BorderSide.none : BorderSide(color: colors.cardRule),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: nameSlot),
              const SizedBox(width: 12),
              if (badgeWidget != null)
                badgeWidget
              else if (tag.isNotEmpty)
                Text(
                  tag.toUpperCase(),
                  style: s
                      .caps(12, tracking: 0.14, color: colors.muted)
                      .copyWith(height: 1.4),
                ),
            ],
          ),
          if (price.trim().isNotEmpty) ...[
            const SizedBox(height: 28),
            priceSlot(60),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(note, style: s.body(15, height: 1.45, color: colors.muted)),
          ],
          if (featureList != null) ...[
            SizedBox(height: note.isNotEmpty ? 22 : 28),
            Container(
              padding: const EdgeInsets.only(top: 22),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.rule)),
              ),
              child: Text(
                'INCLUYE',
                style: s
                    .caps(12, tracking: 0.14, color: colors.muted)
                    .copyWith(height: 1.4),
              ),
            ),
            const SizedBox(height: 14),
            featureList,
          ],
          if (button != null) ...[
            const Spacer(),
            const SizedBox(height: 36),
            button,
          ],
        ],
      ),
    );
  }
}
