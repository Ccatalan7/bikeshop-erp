import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'text_formatting_toolbar.dart';
import 'website_block_content_presenters.dart';

/// Shared visitor content for the schema-defined Stats collection.
///
/// `metrics` is canonical. `stats` and `items` remain read/write aliases for
/// persisted legacy blocks through [WebsiteInlineRepeaterTarget].
class WebsiteStatsBlockContent extends StatelessWidget {
  const WebsiteStatsBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    this.presenters,
    this.padding = const EdgeInsets.symmetric(
      vertical: 64,
      horizontal: 24,
    ),
  });

  static const rootKey = ValueKey<String>('website-stats-content-root');
  static const frameKey = ValueKey<String>('website-stats-content-frame');
  static const titleKey = ValueKey<String>('website-stats-title');
  static const collectionKey = ValueKey<String>('website-stats-collection');

  static ValueKey<String> metricKey(int index) =>
      ValueKey<String>('website-stat-$index');

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final metrics = _firstMapList(
      data,
      const <String>['metrics', 'stats', 'items'],
    );
    if (metrics.isEmpty) {
      return const SizedBox.shrink(key: rootKey);
    }

    final theme = Theme.of(context);
    final rawTitle = _firstString(data, const <String>['title']);
    final title = rawTitle.trim().isEmpty ? 'Indicadores' : rawTitle.trim();
    final titleFormatting = _formatting(data['titleFormatting']);
    final titleSlot = WebsiteInlineTextSlot(
      id: 'stats.title',
      value: rawTitle,
      valueKeys: const <String>['title'],
      baseStyle: (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
        fontFamily: headingFont,
      ),
      formatting: titleFormatting,
      formattingKeys: const <String>['titleFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Indicadores',
      displayTransform: (value) =>
          value.trim().isEmpty ? 'Indicadores' : value.trim(),
    );

    return Padding(
      key: rootKey,
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          key: frameKey,
          constraints: const BoxConstraints(maxWidth: 1000),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth =
                  constraints.hasBoundedWidth ? constraints.maxWidth : 1000.0;
              final compact = availableWidth < 600;
              final itemWidth =
                  compact ? availableWidth : math.min(220.0, availableWidth);

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
                      for (var index = 0; index < metrics.length; index++)
                        SizedBox(
                          key: metricKey(index),
                          width: itemWidth,
                          child: _StatsMetricCard(
                            metric: metrics[index],
                            index: index,
                            primaryColor: primaryColor,
                            accentColor: accentColor,
                            headingFont: headingFont,
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

class _StatsMetricCard extends StatelessWidget {
  const _StatsMetricCard({
    required this.metric,
    required this.index,
    required this.primaryColor,
    required this.accentColor,
    required this.headingFont,
    required this.bodyFont,
    required this.presenters,
  });

  final Map<String, dynamic> metric;
  final int index;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawValue = _firstString(metric, const <String>['value']);
    final rawSuffix = _firstString(metric, const <String>['suffix']);
    final rawLabel = _firstString(metric, const <String>['label']);
    final displayLabel =
        rawLabel.trim().isEmpty ? 'Indicador' : rawLabel.trim();
    final repeaterTarget = _target(
      metric,
      index: index,
      collectionKeys: const <String>['metrics', 'stats', 'items'],
    );
    final valueStyle =
        (theme.textTheme.displaySmall ?? const TextStyle()).copyWith(
      fontFamily: headingFont,
      color: primaryColor,
      fontWeight: FontWeight.bold,
    );
    final suffixStyle = valueStyle.copyWith(
      fontSize: (valueStyle.fontSize ?? 36) * 0.72,
    );
    final labelStyle =
        (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontFamily: bodyFont,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueSlot = WebsiteInlineTextSlot(
      id: 'stats.metric.$index.value',
      value: rawValue,
      valueKeys: const <String>['value'],
      baseStyle: valueStyle,
      formatting: _formatting(metric['valueFormatting']),
      formattingKeys: const <String>['valueFormatting'],
      textAlign: TextAlign.center,
      placeholder: '0',
      repeaterTarget: repeaterTarget,
    );
    final suffixSlot = WebsiteInlineTextSlot(
      id: 'stats.metric.$index.suffix',
      value: rawSuffix,
      valueKeys: const <String>['suffix'],
      baseStyle: suffixStyle,
      formatting: _formatting(metric['suffixFormatting']),
      formattingKeys: const <String>['suffixFormatting'],
      textAlign: TextAlign.center,
      placeholder: '+',
      repeaterTarget: repeaterTarget,
    );
    final labelSlot = WebsiteInlineTextSlot(
      id: 'stats.metric.$index.label',
      value: rawLabel,
      valueKeys: const <String>['label'],
      baseStyle: labelStyle,
      formatting: _formatting(metric['labelFormatting']),
      formattingKeys: const <String>['labelFormatting'],
      textAlign: TextAlign.center,
      placeholder: 'Indicador',
      displayTransform: (value) =>
          value.trim().isEmpty ? 'Indicador' : value.trim(),
      repeaterTarget: repeaterTarget,
    );
    final icon = _metricIcon(metric['icon']);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon.$1,
                size: 28,
                color: primaryColor,
                semanticLabel: icon.$2,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Flexible(
                  child: _presentText(
                    context,
                    valueSlot,
                    fallbackText: rawValue,
                  ),
                ),
                if (rawSuffix.isNotEmpty)
                  Flexible(
                    child: _presentText(
                      context,
                      suffixSlot,
                      fallbackText: rawSuffix,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _presentText(
              context,
              labelSlot,
              fallbackText: displayLabel,
            ),
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

  static (IconData, String)? _metricIcon(Object? raw) {
    return switch (raw?.toString().trim()) {
      'military_tech' => (Icons.military_tech, 'Medalla'),
      'emoji_events' => (Icons.emoji_events, 'Trofeo'),
      'directions_bike' => (Icons.directions_bike, 'Bicicleta'),
      'insights' => (Icons.insights, 'Indicadores'),
      _ => null,
    };
  }
}

WebsiteInlineRepeaterTarget _target(
  Map<String, dynamic> item, {
  required int index,
  required List<String> collectionKeys,
}) {
  final persistedId = item['id'];
  final hasPersistedId =
      persistedId != null && persistedId.toString().trim().isNotEmpty;
  return WebsiteInlineRepeaterTarget(
    collectionKeys: collectionKeys,
    itemIndex: index,
    identityKey: hasPersistedId ? 'id' : null,
    identityValue: hasPersistedId ? persistedId : null,
  );
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
