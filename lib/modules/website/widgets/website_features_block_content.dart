import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';
import 'website_block_icon_resolver.dart';

/// Shared visitor content for a Website Builder Features block.
///
/// The persisted `features` collection is canonical. `items` remains a
/// read/write migration alias, but an explicitly present canonical collection
/// always wins, including when it is empty.
class WebsiteFeaturesBlockContent extends StatelessWidget {
  const WebsiteFeaturesBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
  });

  static const rootKey = ValueKey<String>('website-features-root');
  static const headerKey = ValueKey<String>('website-features-header');
  static const titleKey = ValueKey<String>('website-features-title');
  static const collectionKey = ValueKey<String>('website-features-collection');
  static const gridKey = ValueKey<String>('website-features-grid');
  static const listKey = ValueKey<String>('website-features-list');

  static ValueKey<String> itemKey(int index) =>
      ValueKey<String>('website-features-item-$index');

  static ValueKey<String> itemTitleKey(int index) =>
      ValueKey<String>('website-features-item-$index-title');

  static ValueKey<String> itemDescriptionKey(int index) =>
      ValueKey<String>('website-features-item-$index-description');

  final Map<String, dynamic> data;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rawTitle = (data['title'] ?? 'Por qué elegirnos').toString();
    final resolvedTitle =
        rawTitle.trim().isEmpty ? 'Características' : rawTitle.trim();
    final features = _resolveCollection(
      data,
      canonicalKey: 'features',
      aliases: const <String>['items'],
    );
    final layout = data['layout']?.toString().trim().toLowerCase() == 'list'
        ? 'list'
        : 'grid';
    final titleFormatting = _formatting(data['titleFormatting']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final usefulWidth =
            (frameWidth - resolvedPadding.horizontal).clamp(0.0, 1100.0);
        final isCompact = usefulWidth < 600;
        final titleSize = isCompact
            ? 26.0
            : usefulWidth < 1100
                ? 34.0
                : 40.0;
        final titleStyle = TextStyle(
          fontFamily: headingFont,
          fontSize: titleSize,
          fontWeight: FontWeight.w700,
          height: 1.15,
          color: Theme.of(context).colorScheme.onSurface,
        );
        final titleSlot = WebsiteInlineTextSlot(
          id: 'features.title',
          value: rawTitle,
          valueKeys: const <String>['title'],
          baseStyle: titleStyle,
          formatting: titleFormatting,
          formattingKeys: const <String>['titleFormatting'],
          textAlign: TextAlign.center,
          placeholder: 'Título de características',
          displayTransform: (value) {
            final trimmed = value.trim();
            return trimmed.isEmpty ? 'Características' : trimmed;
          },
        );

        return Container(
          key: rootKey,
          width: double.infinity,
          color: backgroundColor,
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyedSubtree(
                    key: headerKey,
                    child: KeyedSubtree(
                      key: titleKey,
                      child: _presentText(
                        context,
                        titleSlot,
                        publicValue: resolvedTitle,
                      ),
                    ),
                  ),
                  if (features.isNotEmpty) ...[
                    const SizedBox(height: 48),
                    KeyedSubtree(
                      key: collectionKey,
                      child: layout == 'list'
                          ? _FeaturesList(
                              features: features,
                              primaryColor: primaryColor,
                              headingFont: headingFont,
                              bodyFont: bodyFont,
                              presenters: presenters,
                            )
                          : _FeaturesGrid(
                              features: features,
                              primaryColor: primaryColor,
                              headingFont: headingFont,
                              bodyFont: bodyFont,
                              presenters: presenters,
                              isCompact: isCompact,
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _presentText(
    BuildContext context,
    WebsiteInlineTextSlot slot, {
    required String publicValue,
  }) {
    return presenters?.text?.call(context, slot) ??
        Text(
          publicValue,
          style: slot.formatting.applyTo(slot.baseStyle),
          textAlign: slot.resolvedTextAlign,
          maxLines: slot.maxLines,
        );
  }
}

class _FeaturesGrid extends StatelessWidget {
  const _FeaturesGrid({
    required this.features,
    required this.primaryColor,
    required this.headingFont,
    required this.bodyFont,
    required this.presenters,
    required this.isCompact,
  });

  final List<Map<String, dynamic>> features;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return Wrap(
          key: WebsiteFeaturesBlockContent.gridKey,
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: [
            for (var index = 0; index < features.length; index++)
              SizedBox(
                key: WebsiteFeaturesBlockContent.itemKey(index),
                width: isCompact ? compactWidth : 320,
                child: _FeatureGridCard(
                  item: features[index],
                  index: index,
                  primaryColor: primaryColor,
                  headingFont: headingFont,
                  bodyFont: bodyFont,
                  presenters: presenters,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FeatureGridCard extends StatelessWidget {
  const _FeatureGridCard({
    required this.item,
    required this.index,
    required this.primaryColor,
    required this.headingFont,
    required this.bodyFont,
    required this.presenters,
  });

  final Map<String, dynamic> item;
  final int index;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  @override
  Widget build(BuildContext context) {
    final titleStyle =
        (Theme.of(context).textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontFamily: headingFont,
      fontWeight: FontWeight.w600,
    );
    final descriptionStyle =
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontFamily: bodyFont,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1.5,
    );
    final title = (item['title'] ?? '').toString();
    final description = (item['description'] ?? '').toString();
    final target = WebsiteInlineRepeaterTarget(
      collectionKeys: const <String>['features', 'items'],
      itemIndex: index,
    );
    final titleSlot = WebsiteInlineTextSlot(
      id: 'features.item.$index.title',
      value: title,
      valueKeys: const <String>['title'],
      baseStyle: titleStyle,
      formatting: _formatting(item['titleFormatting']),
      formattingKeys: const <String>['titleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Título',
      repeaterTarget: target,
    );
    final descriptionSlot = WebsiteInlineTextSlot(
      id: 'features.item.$index.description',
      value: description,
      valueKeys: const <String>['description'],
      baseStyle: descriptionStyle,
      formatting: _formatting(item['descriptionFormatting']),
      formattingKeys: const <String>['descriptionFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Descripción',
      repeaterTarget: target,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              WebsiteBlockIconResolver.resolve(item['icon']?.toString()),
              size: 48,
              color: primaryColor,
            ),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: WebsiteFeaturesBlockContent.itemTitleKey(index),
              child: _presentItemText(context, presenters, titleSlot),
            ),
            if (description.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              KeyedSubtree(
                key: WebsiteFeaturesBlockContent.itemDescriptionKey(index),
                child: _presentItemText(
                  context,
                  presenters,
                  descriptionSlot,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeaturesList extends StatelessWidget {
  const _FeaturesList({
    required this.features,
    required this.primaryColor,
    required this.headingFont,
    required this.bodyFont,
    required this.presenters,
  });

  final List<Map<String, dynamic>> features;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: WebsiteFeaturesBlockContent.listKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < features.length; index++)
          Padding(
            key: WebsiteFeaturesBlockContent.itemKey(index),
            padding: EdgeInsets.only(
              bottom: index == features.length - 1 ? 0 : 32,
            ),
            child: _FeatureListItem(
              item: features[index],
              index: index,
              primaryColor: primaryColor,
              headingFont: headingFont,
              bodyFont: bodyFont,
              presenters: presenters,
            ),
          ),
      ],
    );
  }
}

class _FeatureListItem extends StatelessWidget {
  const _FeatureListItem({
    required this.item,
    required this.index,
    required this.primaryColor,
    required this.headingFont,
    required this.bodyFont,
    required this.presenters,
  });

  final Map<String, dynamic> item;
  final int index;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  @override
  Widget build(BuildContext context) {
    final title = (item['title'] ?? '').toString();
    final description = (item['description'] ?? '').toString();
    final target = WebsiteInlineRepeaterTarget(
      collectionKeys: const <String>['features', 'items'],
      itemIndex: index,
    );
    final titleSlot = WebsiteInlineTextSlot(
      id: 'features.item.$index.title',
      value: title,
      valueKeys: const <String>['title'],
      baseStyle: TextStyle(
        fontFamily: headingFont,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      formatting: _formatting(item['titleFormatting']),
      formattingKeys: const <String>['titleFormatting'],
      placeholder: 'Título',
      repeaterTarget: target,
    );
    final descriptionSlot = WebsiteInlineTextSlot(
      id: 'features.item.$index.description',
      value: description,
      valueKeys: const <String>['description'],
      baseStyle: TextStyle(
        fontFamily: bodyFont,
        fontSize: 15,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
      formatting: _formatting(item['descriptionFormatting']),
      formattingKeys: const <String>['descriptionFormatting'],
      placeholder: 'Descripción',
      repeaterTarget: target,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            WebsiteBlockIconResolver.resolve(item['icon']?.toString()),
            size: 28,
            color: primaryColor,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeyedSubtree(
                key: WebsiteFeaturesBlockContent.itemTitleKey(index),
                child: _presentItemText(context, presenters, titleSlot),
              ),
              if (description.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                KeyedSubtree(
                  key: WebsiteFeaturesBlockContent.itemDescriptionKey(index),
                  child: _presentItemText(
                    context,
                    presenters,
                    descriptionSlot,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

Widget _presentItemText(
  BuildContext context,
  WebsiteBlockContentPresenters? presenters,
  WebsiteInlineTextSlot slot,
) {
  return presenters?.text?.call(context, slot) ??
      Text(
        slot.value,
        style: slot.formatting.applyTo(slot.baseStyle),
        textAlign: slot.resolvedTextAlign,
        maxLines: slot.maxLines,
      );
}

List<Map<String, dynamic>> _resolveCollection(
  Map<String, dynamic> data, {
  required String canonicalKey,
  required List<String> aliases,
}) {
  Object? raw;
  if (data.containsKey(canonicalKey)) {
    raw = data[canonicalKey];
  } else {
    for (final alias in aliases) {
      if (data.containsKey(alias)) {
        raw = data[alias];
        break;
      }
    }
  }
  if (raw is! List) return const <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

TextFormatting _formatting(Object? raw) {
  if (raw is! Map) return const TextFormatting();
  return TextFormatting.fromJson(Map<String, dynamic>.from(raw));
}
