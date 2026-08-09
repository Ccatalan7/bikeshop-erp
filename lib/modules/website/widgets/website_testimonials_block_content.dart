import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';

/// Shared visitor content for the schema-defined Testimonials collection.
///
/// `comment` is canonical. `quote` and `text` remain legacy aliases described
/// to the editor bridge by each nested slot.
class WebsiteTestimonialsBlockContent extends StatelessWidget {
  const WebsiteTestimonialsBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.backgroundColor,
    this.padding = const EdgeInsets.symmetric(
      vertical: 64,
      horizontal: 24,
    ),
  });

  static const rootKey = ValueKey<String>('website-testimonials-content-root');
  static const frameKey =
      ValueKey<String>('website-testimonials-content-frame');
  static const titleKey = ValueKey<String>('website-testimonials-title');
  static const collectionKey =
      ValueKey<String>('website-testimonials-collection');

  static ValueKey<String> testimonialKey(int index) =>
      ValueKey<String>('website-testimonial-$index');

  final Map<String, dynamic> data;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final testimonials = _firstMapList(
      data,
      const <String>['testimonials', 'items'],
    );
    if (testimonials.isEmpty) {
      return const SizedBox.shrink(key: rootKey);
    }

    final theme = Theme.of(context);
    final rawTitle = _firstString(data, const <String>['title']);
    final title = rawTitle.trim().isEmpty ? 'Testimonios' : rawTitle.trim();
    final titleFormatting = _formatting(data['titleFormatting']);
    final titleSlot = WebsiteInlineTextSlot(
      id: 'testimonials.title',
      value: rawTitle,
      valueKeys: const <String>['title'],
      baseStyle: (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
        fontFamily: headingFont,
      ),
      formatting: titleFormatting,
      formattingKeys: const <String>['titleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Testimonios',
      displayTransform: (value) =>
          value.trim().isEmpty ? 'Testimonios' : value.trim(),
    );

    return ColoredBox(
      color: backgroundColor ??
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
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
                    const SizedBox(height: 40),
                    Wrap(
                      key: collectionKey,
                      spacing: 24,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: <Widget>[
                        for (var index = 0;
                            index < testimonials.length;
                            index++)
                          SizedBox(
                            key: testimonialKey(index),
                            width: cardWidth,
                            child: _TestimonialCard(
                              item: testimonials[index],
                              index: index,
                              primaryColor: primaryColor,
                              bodyFont: bodyFont,
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

class _TestimonialCard extends StatelessWidget {
  const _TestimonialCard({
    required this.item,
    required this.index,
    required this.primaryColor,
    required this.bodyFont,
    required this.presenters,
  });

  final Map<String, dynamic> item;
  final int index;
  final Color primaryColor;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawComment = _firstString(
      item,
      const <String>['comment', 'quote', 'text'],
    );
    final rawName = _firstString(item, const <String>['name']);
    final rawRole = _firstString(item, const <String>['role']);
    final rating = _rating(item['rating']);
    final target = _target(item, index);
    final commentStyle =
        (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: bodyFont,
      fontStyle: FontStyle.italic,
    );
    final nameStyle =
        (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
      fontFamily: bodyFont,
      fontWeight: FontWeight.w700,
    );
    final roleStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontFamily: bodyFont,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final commentSlot = WebsiteInlineTextSlot(
      id: 'testimonials.item.$index.comment',
      value: rawComment,
      valueKeys: const <String>['comment', 'quote', 'text'],
      baseStyle: commentStyle,
      formatting: _formatting(
        item['commentFormatting'] ??
            item['quoteFormatting'] ??
            item['textFormatting'],
      ),
      formattingKeys: const <String>[
        'commentFormatting',
        'quoteFormatting',
        'textFormatting',
      ],
      placeholder: 'Testimonio del cliente',
      repeaterTarget: target,
    );
    final nameSlot = WebsiteInlineTextSlot(
      id: 'testimonials.item.$index.name',
      value: rawName,
      valueKeys: const <String>['name'],
      baseStyle: nameStyle,
      formatting: _formatting(item['nameFormatting']),
      formattingKeys: const <String>['nameFormatting'],
      placeholder: 'Nombre',
      repeaterTarget: target,
    );
    final roleSlot = WebsiteInlineTextSlot(
      id: 'testimonials.item.$index.role',
      value: rawRole,
      valueKeys: const <String>['role'],
      baseStyle: roleStyle,
      formatting: _formatting(item['roleFormatting']),
      formattingKeys: const <String>['roleFormatting'],
      placeholder: 'Rol o título',
      repeaterTarget: target,
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.format_quote,
              color: primaryColor,
              size: 32,
            ),
            if (rawComment.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              _presentText(
                context,
                commentSlot,
                fallbackText: rawComment.trim(),
              ),
            ],
            if (rating != null) ...<Widget>[
              const SizedBox(height: 24),
              Semantics(
                container: true,
                label: 'Valoración: $rating de 5',
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var star = 0; star < 5; star++)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            star < rating ? Icons.star : Icons.star_border,
                            color: star < rating
                                ? primaryColor
                                : theme.colorScheme.onSurfaceVariant,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (rawName.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              _presentText(
                context,
                nameSlot,
                fallbackText: rawName.trim(),
              ),
            ],
            if (rawRole.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              _presentText(
                context,
                roleSlot,
                fallbackText: rawRole.trim(),
              ),
            ],
          ],
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

  static int? _rating(Object? raw) {
    final parsed = switch (raw) {
      num number => number.round(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
    return parsed?.clamp(1, 5);
  }

  static WebsiteInlineRepeaterTarget _target(
    Map<String, dynamic> item,
    int index,
  ) {
    final persistedId = item['id'];
    final hasPersistedId =
        persistedId != null && persistedId.toString().trim().isNotEmpty;
    return WebsiteInlineRepeaterTarget(
      collectionKeys: const <String>['testimonials', 'items'],
      itemIndex: index,
      identityKey: hasPersistedId ? 'id' : null,
      identityValue: hasPersistedId ? persistedId : null,
    );
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

TextFormatting _formatting(Object? raw) {
  if (raw is! Map) return const TextFormatting();
  return TextFormatting.fromJson(Map<String, dynamic>.from(raw));
}
