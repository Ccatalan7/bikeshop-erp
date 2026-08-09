import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/website_action.dart';
import 'text_formatting_toolbar.dart';
import 'website_action_button.dart';
import 'website_block_content_presenters.dart';

/// Shared visitor content for the schema-defined Pricing collection.
///
/// Public, Preview and Edit use one card tree. Edit replaces only typed text
/// and action leaves; structural collection operations remain inspector-owned.
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
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(
      vertical: 64,
      horizontal: 24,
    ),
  });

  static const rootKey = ValueKey<String>('website-pricing-content-root');
  static const frameKey = ValueKey<String>('website-pricing-content-frame');
  static const titleKey = ValueKey<String>('website-pricing-title');
  static const subtitleKey = ValueKey<String>('website-pricing-subtitle');
  static const collectionKey = ValueKey<String>('website-pricing-collection');

  static ValueKey<String> planKey(int index) =>
      ValueKey<String>('website-pricing-plan-$index');

  static ValueKey<String> actionKey(int index) =>
      ValueKey<String>('website-pricing-action-$index');

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final bool previewMode;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final WebsiteBlockContentPresenters? presenters;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final plans = _firstMapList(
      data,
      const <String>['plans', 'items'],
    );
    if (plans.isEmpty) {
      return const SizedBox.shrink(key: rootKey);
    }

    final theme = Theme.of(context);
    final rawTitle = _firstString(data, const <String>['title']);
    final rawSubtitle = _firstString(data, const <String>['subtitle']);
    final title =
        rawTitle.trim().isEmpty ? 'Planes y Precios' : rawTitle.trim();
    final subtitle = rawSubtitle.trim();
    final titleFormatting = _formatting(data['titleFormatting']);
    final subtitleFormatting = _formatting(data['subtitleFormatting']);
    final titleSlot = WebsiteInlineTextSlot(
      id: 'pricing.title',
      value: rawTitle,
      valueKeys: const <String>['title'],
      baseStyle: (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
        fontFamily: headingFont,
      ),
      formatting: titleFormatting,
      formattingKeys: const <String>['titleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Planes y Precios',
      displayTransform: (value) =>
          value.trim().isEmpty ? 'Planes y Precios' : value.trim(),
    );
    final subtitleSlot = WebsiteInlineTextSlot(
      id: 'pricing.subtitle',
      value: rawSubtitle,
      valueKeys: const <String>['subtitle'],
      baseStyle: (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontFamily: bodyFont,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      formatting: subtitleFormatting,
      formattingKeys: const <String>['subtitleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Subtítulo opcional',
    );

    return ColoredBox(
      color: backgroundColor ??
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
      child: Padding(
        key: rootKey,
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            key: frameKey,
            constraints: const BoxConstraints(maxWidth: 1100),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth =
                    constraints.hasBoundedWidth ? constraints.maxWidth : 1100.0;
                final compact = availableWidth < 600;
                final cardWidth =
                    compact ? availableWidth : math.min(320.0, availableWidth);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    KeyedSubtree(
                      key: titleKey,
                      child: _presentText(
                        context,
                        titleSlot,
                        fallbackText: title,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      KeyedSubtree(
                        key: subtitleKey,
                        child: _presentText(
                          context,
                          subtitleSlot,
                          fallbackText: subtitle,
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    Wrap(
                      key: collectionKey,
                      spacing: 24,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: <Widget>[
                        for (var index = 0; index < plans.length; index++)
                          SizedBox(
                            key: planKey(index),
                            width: cardWidth,
                            child: _PricingPlanCard(
                              plan: plans[index],
                              index: index,
                              primaryColor: primaryColor,
                              accentColor: accentColor,
                              bodyFont: bodyFont,
                              previewMode: previewMode,
                              onNavigate: onNavigate,
                              isNavigationEligible: isNavigationEligible,
                              presenters: presenters,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _presentText(
    BuildContext context,
    WebsiteInlineTextSlot slot, {
    required String fallbackText,
  }) {
    return presenters?.text?.call(context, slot) ??
        Text(
          fallbackText,
          style: slot.formatting.applyTo(slot.baseStyle),
          textAlign: slot.resolvedTextAlign,
        );
  }
}

class _PricingPlanCard extends StatelessWidget {
  const _PricingPlanCard({
    required this.plan,
    required this.index,
    required this.primaryColor,
    required this.accentColor,
    required this.bodyFont,
    required this.previewMode,
    required this.onNavigate,
    required this.isNavigationEligible,
    required this.presenters,
  });

  final Map<String, dynamic> plan;
  final int index;
  final Color primaryColor;
  final Color accentColor;
  final String? bodyFont;
  final bool previewMode;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final WebsiteBlockContentPresenters? presenters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawName = _firstString(plan, const <String>['name']);
    final rawPrice = _firstString(plan, const <String>['price']);
    final features = _stringList(plan['features']);
    final highlighted = _firstBool(
      plan,
      const <String>['highlighted', 'isFeatured'],
    );
    final target = _target(plan, index);
    final nameStyle =
        (theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w700,
    );
    final priceStyle =
        (theme.textTheme.headlineMedium ?? const TextStyle()).copyWith(
      fontFamily: bodyFont,
      color: primaryColor,
      fontWeight: FontWeight.bold,
    );
    final nameSlot = WebsiteInlineTextSlot(
      id: 'pricing.plan.$index.name',
      value: rawName,
      valueKeys: const <String>['name'],
      baseStyle: nameStyle,
      formatting: _formatting(plan['nameFormatting']),
      formattingKeys: const <String>['nameFormatting'],
      placeholder: 'Nombre del plan',
      repeaterTarget: target,
    );
    final priceSlot = WebsiteInlineTextSlot(
      id: 'pricing.plan.$index.price',
      value: rawPrice,
      valueKeys: const <String>['price'],
      baseStyle: priceStyle,
      formatting: _formatting(plan['priceFormatting']),
      formattingKeys: const <String>['priceFormatting'],
      placeholder: '0',
      displayTransform: _priceLabel,
      repeaterTarget: target,
    );
    final resolvedAction = WebsiteActionValue.resolvePrimary(
      plan,
      labelKeys: const <String>['ctaText', 'buttonText'],
      hrefKeys: const <String>['ctaLink', 'buttonLink'],
      variantKeys: const <String>['actionVariant'],
      defaultLabel: 'Seleccionar',
    );
    final displayAction = resolvedAction ??
        WebsiteActionValue(
          label: _firstNonEmptyString(
                plan,
                const <String>['ctaText', 'buttonText'],
              ) ??
              'Seleccionar',
          href: '',
          variant: WebsiteActionVariant.fromStorage(
            plan['actionVariant']?.toString(),
          ),
        );
    final destinationEligible = displayAction.href.trim().isEmpty ||
        isNavigationEligible == null ||
        isNavigationEligible!(displayAction.href);
    final showAction = resolvedAction != null && destinationEligible;
    final cardColor = highlighted
        ? accentColor.withValues(alpha: 0.12)
        : theme.colorScheme.surface;
    final borderColor = highlighted ? accentColor : theme.dividerColor;

    return Card(
      color: cardColor,
      elevation: highlighted ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (highlighted) ...<Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      'Más popular',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (rawName.trim().isNotEmpty)
              _presentText(
                context,
                nameSlot,
                fallbackText: rawName.trim(),
              ),
            if (rawPrice.trim().isNotEmpty) ...<Widget>[
              if (rawName.trim().isNotEmpty) const SizedBox(height: 8),
              _presentText(
                context,
                priceSlot,
                fallbackText: _priceLabel(rawPrice),
              ),
            ],
            if (features.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              for (final feature in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        Icons.check_circle,
                        color: primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: bodyFont,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (showAction) ...<Widget>[
              const SizedBox(height: 24),
              KeyedSubtree(
                key: WebsitePricingBlockContent.actionKey(index),
                child: _buildAction(
                  context,
                  action: displayAction,
                  target: target,
                  highlighted: highlighted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAction(
    BuildContext context, {
    required WebsiteActionValue action,
    required WebsiteInlineRepeaterTarget target,
    required bool highlighted,
  }) {
    final href = action.href.trim();
    final button = WebsiteActionButton(
      action: action,
      // Visitor navigation works in Preview and Public; only Edit
      // (presenters) is inert. Mirrors the standalone-button contract:
      // editor chrome owns the pointer boundary, so a VALID plan CTA stays
      // enabled-looking in Edit through a no-op — Material must never
      // repaint the authored foreground as disabled. Empty hrefs stay
      // truly disabled.
      onPressed: href.isEmpty
          ? null
          : presenters != null
              ? () {}
              : onNavigate != null
                  ? () => onNavigate!(href)
                  : null,
      backgroundColor: highlighted ? accentColor : primaryColor,
      foregroundColor: Colors.white,
      outlineColor: highlighted ? accentColor : primaryColor,
      expand: true,
    );
    final actionPresenter = presenters?.action;
    if (actionPresenter == null) return button;
    return actionPresenter(
      context,
      WebsiteInlineActionSlot(
        id: 'pricing.plan.$index.action',
        action: action,
        labelKeys: const <String>['ctaText', 'buttonText'],
        hrefKeys: const <String>['ctaLink', 'buttonLink'],
        variantKeys: const <String>['actionVariant'],
        child: button,
        repeaterTarget: target,
      ),
    );
  }

  Widget _presentText(
    BuildContext context,
    WebsiteInlineTextSlot slot, {
    required String fallbackText,
  }) {
    return presenters?.text?.call(context, slot) ??
        Text(
          fallbackText,
          style: slot.formatting.applyTo(slot.baseStyle),
          textAlign: slot.resolvedTextAlign,
        );
  }

  static WebsiteInlineRepeaterTarget _target(
    Map<String, dynamic> plan,
    int index,
  ) {
    final persistedId = plan['id'];
    final hasPersistedId =
        persistedId != null && persistedId.toString().trim().isNotEmpty;
    return WebsiteInlineRepeaterTarget(
      collectionKeys: const <String>['plans', 'items'],
      itemIndex: index,
      identityKey: hasPersistedId ? 'id' : null,
      identityValue: hasPersistedId ? persistedId : null,
    );
  }

  static String _priceLabel(String raw) {
    final price = raw.trim();
    final hasCurrency = RegExp(r'[A-Za-z\$]').hasMatch(price);
    if (price.isEmpty) return 'CLP 0';
    return hasCurrency ? price : 'CLP $price';
  }
}

List<Map<String, dynamic>> _firstMapList(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final key in keys) {
    if (!data.containsKey(key)) continue;
    final raw = data[key];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
  return <Map<String, dynamic>>[];
}

String _firstString(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final key in keys) {
    if (data.containsKey(key)) return data[key]?.toString() ?? '';
  }
  return '';
}

String? _firstNonEmptyString(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final key in keys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

bool _firstBool(
  Map<String, dynamic> data,
  List<String> keys,
) {
  for (final key in keys) {
    if (!data.containsKey(key)) continue;
    final value = data[key];
    if (value is bool) return value;
    return value?.toString().trim().toLowerCase() == 'true';
  }
  return false;
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return <String>[];
  return raw
      .where((item) => item != null)
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

TextFormatting _formatting(Object? raw) {
  if (raw is! Map) return const TextFormatting();
  return TextFormatting.fromJson(Map<String, dynamic>.from(raw));
}
