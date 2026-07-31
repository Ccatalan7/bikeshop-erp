import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';
import 'website_block_icon_resolver.dart';

/// Shared visitor content for a Website Builder Services block.
///
/// All persisted services render in order. Desktop/tablet rows contain at most
/// three flex items; below 600px every item occupies the full useful width.
class WebsiteServicesBlockContent extends StatelessWidget {
  const WebsiteServicesBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
  });

  static const rootKey = ValueKey<String>('website-services-root');
  static const headerKey = ValueKey<String>('website-services-header');
  static const titleKey = ValueKey<String>('website-services-title');
  static const collectionKey = ValueKey<String>('website-services-collection');
  static const desktopKey = ValueKey<String>('website-services-desktop-layout');
  static const mobileKey = ValueKey<String>('website-services-mobile-layout');

  static ValueKey<String> rowKey(int index) =>
      ValueKey<String>('website-services-row-$index');

  static ValueKey<String> itemKey(int index) =>
      ValueKey<String>('website-services-item-$index');

  static ValueKey<String> itemTitleKey(int index) =>
      ValueKey<String>('website-services-item-$index-title');

  static ValueKey<String> itemDescriptionKey(int index) =>
      ValueKey<String>('website-services-item-$index-description');

  final Map<String, dynamic> data;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rawTitle = (data['title'] ?? 'Nuestros Servicios').toString();
    final title =
        rawTitle.trim().isEmpty ? 'NUESTROS SERVICIOS' : rawTitle.toUpperCase();
    final services = _resolveCollection(
      data,
      canonicalKey: 'services',
      aliases: const <String>['items'],
    );
    final titleFormatting = _formatting(data['titleFormatting']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final usefulWidth =
            (frameWidth - resolvedPadding.horizontal).clamp(0.0, 1000.0);
        final isCompact = usefulWidth < 600;
        final titleSlot = WebsiteInlineTextSlot(
          id: 'services.title',
          value: rawTitle,
          valueKeys: const <String>['title'],
          baseStyle: TextStyle(
            fontFamily: headingFont,
            fontSize: isCompact ? 17 : 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          formatting: titleFormatting,
          formattingKeys: const <String>['titleFormatting'],
          textAlign: TextAlign.center,
          placeholder: 'Título de servicios',
          displayTransform: (value) {
            final trimmed = value.trim();
            return (trimmed.isEmpty ? 'Nuestros Servicios' : trimmed)
                .toUpperCase();
          },
        );

        return Container(
          key: rootKey,
          width: double.infinity,
          color: backgroundColor ?? const Color(0xFFFAFAFA),
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyedSubtree(
                    key: headerKey,
                    child: KeyedSubtree(
                      key: titleKey,
                      child: presenters?.text?.call(context, titleSlot) ??
                          Text(
                            title,
                            style: titleFormatting.applyTo(titleSlot.baseStyle),
                            textAlign: titleSlot.resolvedTextAlign,
                            maxLines: titleSlot.maxLines,
                          ),
                    ),
                  ),
                  if (services.isNotEmpty) ...[
                    const SizedBox(height: 40),
                    KeyedSubtree(
                      key: collectionKey,
                      child: isCompact
                          ? _ServicesMobileList(
                              services: services,
                              primaryColor: primaryColor,
                              headingFont: headingFont,
                              bodyFont: bodyFont,
                              presenters: presenters,
                            )
                          : _ServicesDesktopRows(
                              services: services,
                              primaryColor: primaryColor,
                              headingFont: headingFont,
                              bodyFont: bodyFont,
                              presenters: presenters,
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
}

class _ServicesDesktopRows extends StatelessWidget {
  const _ServicesDesktopRows({
    required this.services,
    required this.primaryColor,
    required this.headingFont,
    required this.bodyFont,
    required this.presenters,
  });

  final List<Map<String, dynamic>> services;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  @override
  Widget build(BuildContext context) {
    final rowCount = (services.length / 3).ceil();
    return Column(
      key: WebsiteServicesBlockContent.desktopKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var rowIndex = 0; rowIndex < rowCount; rowIndex++)
          Row(
            key: WebsiteServicesBlockContent.rowKey(rowIndex),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(3, (columnIndex) {
              final index = (rowIndex * 3) + columnIndex;
              if (index >= services.length) {
                return const Expanded(child: SizedBox.shrink());
              }
              return Expanded(
                child: Container(
                  key: WebsiteServicesBlockContent.itemKey(index),
                  decoration: BoxDecoration(
                    border: Border(
                      left: columnIndex > 0
                          ? BorderSide(
                              color: Theme.of(context).dividerColor,
                            )
                          : BorderSide.none,
                      top: rowIndex > 0
                          ? BorderSide(
                              color: Theme.of(context).dividerColor,
                            )
                          : BorderSide.none,
                    ),
                  ),
                  child: _ServiceItem(
                    item: services[index],
                    index: index,
                    primaryColor: primaryColor,
                    headingFont: headingFont,
                    bodyFont: bodyFont,
                    presenters: presenters,
                  ),
                ),
              );
            }),
          ),
      ],
    );
  }
}

class _ServicesMobileList extends StatelessWidget {
  const _ServicesMobileList({
    required this.services,
    required this.primaryColor,
    required this.headingFont,
    required this.bodyFont,
    required this.presenters,
  });

  final List<Map<String, dynamic>> services;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: WebsiteServicesBlockContent.mobileKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < services.length; index++)
          Container(
            key: WebsiteServicesBlockContent.itemKey(index),
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                bottom: index < services.length - 1
                    ? BorderSide(color: Theme.of(context).dividerColor)
                    : BorderSide.none,
              ),
            ),
            child: _ServiceItem(
              item: services[index],
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

class _ServiceItem extends StatelessWidget {
  const _ServiceItem({
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
      collectionKeys: const <String>['services', 'items'],
      itemIndex: index,
    );
    final titleSlot = WebsiteInlineTextSlot(
      id: 'services.item.$index.title',
      value: title,
      valueKeys: const <String>['title'],
      baseStyle: TextStyle(
        fontFamily: headingFont,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      formatting: _formatting(item['titleFormatting']),
      formattingKeys: const <String>['titleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Nombre del servicio',
      repeaterTarget: target,
    );
    final descriptionSlot = WebsiteInlineTextSlot(
      id: 'services.item.$index.description',
      value: description,
      valueKeys: const <String>['description'],
      baseStyle: TextStyle(
        fontFamily: bodyFont,
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
      formatting: _formatting(item['descriptionFormatting']),
      formattingKeys: const <String>['descriptionFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Descripción',
      repeaterTarget: target,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            WebsiteBlockIconResolver.resolve(item['icon']?.toString()),
            size: 32,
            color: primaryColor,
          ),
          const SizedBox(height: 16),
          KeyedSubtree(
            key: WebsiteServicesBlockContent.itemTitleKey(index),
            child: _presentText(context, presenters, titleSlot),
          ),
          if (description.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            KeyedSubtree(
              key: WebsiteServicesBlockContent.itemDescriptionKey(index),
              child: _presentText(context, presenters, descriptionSlot),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _presentText(
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
