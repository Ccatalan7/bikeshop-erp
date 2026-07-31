import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';

/// Shared visitor content for a Website Builder FAQ block.
///
/// Edit, Preview and Public use the same collapsed [ExpansionTile] tree.
/// Editor presenters replace only persisted text leaves; collection controls
/// remain in the inspector and never alter visitor geometry.
class WebsiteFaqBlockContent extends StatelessWidget {
  const WebsiteFaqBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.padding = const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
  });

  static const rootKey = ValueKey<String>('website-faq-root');
  static const headerKey = ValueKey<String>('website-faq-header');
  static const titleKey = ValueKey<String>('website-faq-title');
  static const subtitleKey = ValueKey<String>('website-faq-subtitle');
  static const collectionKey = ValueKey<String>('website-faq-collection');

  static ValueKey<String> itemKey(int index) =>
      ValueKey<String>('website-faq-item-$index');

  static ValueKey<String> questionKey(int index) =>
      ValueKey<String>('website-faq-item-$index-question');

  static ValueKey<String> answerKey(int index) =>
      ValueKey<String>('website-faq-item-$index-answer');

  final Map<String, dynamic> data;
  final Color primaryColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final rawTitle = (data['title'] ?? 'Preguntas frecuentes').toString();
    final title =
        rawTitle.trim().isEmpty ? 'Preguntas frecuentes' : rawTitle.trim();
    final subtitle = (data['subtitle'] ?? '').toString();
    final items = _resolveItems(data);
    final titleFormatting = _formatting(data['titleFormatting']);
    final subtitleFormatting = _formatting(data['subtitleFormatting']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final usefulWidth =
            (frameWidth - resolvedPadding.horizontal).clamp(0.0, 900.0);
        final isCompact = usefulWidth < 600;
        final titleSize = isCompact
            ? 26.0
            : usefulWidth < 900
                ? 34.0
                : 40.0;
        final titleSlot = WebsiteInlineTextSlot(
          id: 'faq.title',
          value: rawTitle,
          valueKeys: const <String>['title'],
          baseStyle: TextStyle(
            fontFamily: headingFont,
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          formatting: titleFormatting,
          formattingKeys: const <String>['titleFormatting'],
          textAlign: TextAlign.center,
          placeholder: 'Título de FAQ',
          displayTransform: (value) {
            final trimmed = value.trim();
            return trimmed.isEmpty ? 'Preguntas frecuentes' : trimmed;
          },
        );
        final subtitleSlot = WebsiteInlineTextSlot(
          id: 'faq.subtitle',
          value: subtitle,
          valueKeys: const <String>['subtitle'],
          baseStyle: TextStyle(
            fontFamily: bodyFont,
            fontSize: 17,
            height: 1.45,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          formatting: subtitleFormatting,
          formattingKeys: const <String>['subtitleFormatting'],
          textAlign: TextAlign.center,
          placeholder: 'Subtítulo opcional',
        );

        return Padding(
          key: rootKey,
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KeyedSubtree(
                    key: headerKey,
                    child: Column(
                      children: [
                        KeyedSubtree(
                          key: titleKey,
                          child: presenters?.text?.call(context, titleSlot) ??
                              Text(
                                title,
                                style: titleFormatting
                                    .applyTo(titleSlot.baseStyle),
                                textAlign: titleSlot.resolvedTextAlign,
                                maxLines: titleSlot.maxLines,
                              ),
                        ),
                        if (subtitle.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          KeyedSubtree(
                            key: subtitleKey,
                            child:
                                presenters?.text?.call(context, subtitleSlot) ??
                                    Text(
                                      subtitle.trim(),
                                      style: subtitleFormatting
                                          .applyTo(subtitleSlot.baseStyle),
                                      textAlign: subtitleSlot.resolvedTextAlign,
                                      maxLines: subtitleSlot.maxLines,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    Column(
                      key: collectionKey,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var index = 0; index < items.length; index++)
                          _FaqItem(
                            key: itemKey(index),
                            item: items[index],
                            index: index,
                            primaryColor: primaryColor,
                            headingFont: headingFont,
                            bodyFont: bodyFont,
                            presenters: presenters,
                          ),
                      ],
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

class _FaqItem extends StatelessWidget {
  const _FaqItem({
    super.key,
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
    final theme = Theme.of(context);
    final question = (item['question'] ?? '').toString();
    final answer = (item['answer'] ?? '').toString();
    final target = WebsiteInlineRepeaterTarget(
      collectionKeys: const <String>['items'],
      itemIndex: index,
    );
    final questionSlot = WebsiteInlineTextSlot(
      id: 'faq.item.$index.question',
      value: question,
      valueKeys: const <String>['question'],
      baseStyle: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
        fontFamily: headingFont,
        fontWeight: FontWeight.w600,
      ),
      formatting: _formatting(item['questionFormatting']),
      formattingKeys: const <String>['questionFormatting'],
      placeholder: 'Pregunta',
      repeaterTarget: target,
    );
    final answerSlot = WebsiteInlineTextSlot(
      id: 'faq.item.$index.answer',
      value: answer,
      valueKeys: const <String>['answer'],
      baseStyle: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontFamily: bodyFont,
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
      formatting: _formatting(item['answerFormatting']),
      formattingKeys: const <String>['answerFormatting'],
      placeholder: 'Respuesta',
      repeaterTarget: target,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: primaryColor,
          collapsedIconColor: primaryColor,
          title: KeyedSubtree(
            key: WebsiteFaqBlockContent.questionKey(index),
            child: _presentText(context, presenters, questionSlot),
          ),
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: KeyedSubtree(
                key: WebsiteFaqBlockContent.answerKey(index),
                child: _presentText(context, presenters, answerSlot),
              ),
            ),
          ],
        ),
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

List<Map<String, dynamic>> _resolveItems(Map<String, dynamic> data) {
  if (!data.containsKey('items')) return const <Map<String, dynamic>>[];
  final raw = data['items'];
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
