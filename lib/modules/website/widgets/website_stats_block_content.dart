import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_type.dart';
import 'package:vinabike_public_core/modules/website/models/website_section_content.dart';
import 'package:vinabike_public_core/modules/website/theme/website_section_palette.dart';

import 'website_block_content_presenters.dart';
import 'website_section_frame.dart';

/// Shared visitor content for the schema-defined Stats collection: a band
/// (dark by default) with the section's header and the figures in a row
/// under a rule, a line between them; two columns on a tablet or a phone.
/// The HTML storefront draws the same (`StatsSectionView`).
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
    this.padding,
    this.paintSurface = true,
    this.setting,
  });

  static const rootKey = ValueKey<String>('website-stats-content-root');
  static const titleKey = ValueKey<String>('website-stats-title');
  static const collectionKey = ValueKey<String>('website-stats-collection');

  static ValueKey<String> metricKey(int index) =>
      ValueKey<String>('website-stat-$index');

  static ValueKey<String> liveValueKey(int index) =>
      ValueKey<String>('website-stat-live-value-$index');

  static const _collection = <String>['metrics', 'stats', 'items'];

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;
  final WebsiteBlockContentPresenters? presenters;

  /// The padding the operator set; `null` keeps the design's.
  final EdgeInsetsGeometry? padding;
  final bool paintSurface;

  /// The store's settings, where a Google figure reads the synced score and
  /// review count.
  final String Function(String key)? setting;

  @override
  Widget build(BuildContext context) {
    final metrics = websiteSectionItems(data, 'metrics', const [
      'stats',
      'items',
    ]);
    final hasHeader = [
      'eyebrow',
      'title',
      'subtitle',
    ].any((key) => (data[key]?.toString() ?? '').trim().isNotEmpty);
    if (metrics.isEmpty && !hasHeader) {
      return const SizedBox.shrink(key: rootKey);
    }
    return KeyedSubtree(
      key: rootKey,
      child: WebsiteSectionBand(
        tone: WebsiteSectionTone.of(WebsiteBlockType.stats, data),
        primaryColor: primaryColor,
        accentColor: accentColor,
        headingFont: headingFont,
        bodyFont: bodyFont,
        padding: padding,
        paintSurface: paintSurface,
        paddingFor: (metrics) => switch (metrics.width) {
          WebsiteSectionWidth.desktop =>
            const EdgeInsets.fromLTRB(32, 104, 32, 96),
          WebsiteSectionWidth.tablet =>
            const EdgeInsets.fromLTRB(32, 88, 32, 80),
          WebsiteSectionWidth.phone =>
            const EdgeInsets.fromLTRB(20, 64, 20, 56),
        },
        builder: (context, scope) {
          final header = WebsiteSectionHeader(
            key: titleKey,
            scope: scope,
            data: data,
            idPrefix: 'stats',
            presenters: presenters,
            titleSize: switch (scope.metrics.width) {
              WebsiteSectionWidth.desktop => 56,
              WebsiteSectionWidth.tablet => 48,
              WebsiteSectionWidth.phone => 38,
            },
            titleHeight: scope.isPhone ? 1.05 : 1.04,
            titleMaxWidth: 680,
            eyebrowGap: 18,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!header.isEmpty) header,
              if (metrics.isNotEmpty) ...[
                if (!header.isEmpty)
                  SizedBox(
                    height: switch (scope.metrics.width) {
                      WebsiteSectionWidth.desktop => 64,
                      WebsiteSectionWidth.tablet => 48,
                      WebsiteSectionWidth.phone => 36,
                    },
                  ),
                _grid(context, scope, metrics),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    WebsiteSectionScope scope,
    List<(int, Map<String, dynamic>)> metrics,
  ) {
    final desktop = scope.isDesktop;
    final columns = websiteStatsColumns(metrics.length, desktop: desktop);
    // A desktop row: a line between the figures and 28 after it (CSS's
    // column gap); a tablet or phone row: no gap, a line under each row.
    final gap = desktop ? 28.0 : 0.0;
    final width = scope.contentWidth;
    final columnWidth = (width - gap * (columns - 1)) / columns;
    final rule = BorderSide(color: scope.colors.rule);
    final rows = <Widget>[];
    for (var start = 0; start < metrics.length; start += columns) {
      final row = metrics.skip(start).take(columns).toList();
      rows.add(
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: row.length * columnWidth + (row.length - 1) * gap,
            child: Table(
              columnWidths: {
                for (var column = 0; column < row.length; column++)
                  column: FixedColumnWidth(
                    column == 0 ? columnWidth : columnWidth + gap,
                  ),
              },
              border: desktop
                  ? TableBorder(verticalInside: rule)
                  : TableBorder(bottom: rule),
              children: [
                TableRow(
                  children: [
                    for (final (column, (index, metric)) in row.indexed)
                      Padding(
                        key: metricKey(index),
                        padding: desktop
                            ? EdgeInsets.fromLTRB(
                                column == 0 ? 0 : gap,
                                30,
                                28,
                                0,
                              )
                            : const EdgeInsets.fromLTRB(0, 22, 12, 20),
                        child: _metric(context, scope, metric, index),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      key: collectionKey,
      decoration: BoxDecoration(border: Border(top: rule)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  Widget _metric(
    BuildContext context,
    WebsiteSectionScope scope,
    Map<String, dynamic> metric,
    int index,
  ) {
    final target = websiteSectionTarget(
      metric,
      index: index,
      collectionKeys: _collection,
    );
    final (valueSize, suffixSize) = switch (scope.metrics.width) {
      WebsiteSectionWidth.desktop => (76.0, 26.0),
      WebsiteSectionWidth.tablet => (60.0, 22.0),
      WebsiteSectionWidth.phone => (48.0, 18.0),
    };
    final figure = websiteStatsFigure(
      metric,
      setting: setting ?? (_) => '',
    );
    final suffix = figure.suffix;
    final label = websiteSectionText(metric, const ['label']);
    final valueStyle = scope.heading(valueSize, height: 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              // A Google figure is read from the sync, never written here.
              child: figure.live
                  ? Text(
                      figure.value,
                      key: liveValueKey(index),
                      style: valueStyle,
                    )
                  : websiteSectionSlot(
                      context,
                      presenters,
                      WebsiteInlineTextSlot(
                        id: 'stats.metric.$index.value',
                        value: figure.value,
                        valueKeys: const <String>['value'],
                        baseStyle: valueStyle,
                        formatting: websiteSectionFormatting(
                          metric['valueFormatting'],
                        ),
                        formattingKeys: const <String>['valueFormatting'],
                        placeholder: '0',
                        repeaterTarget: target,
                      ),
                    ),
            ),
            if (suffix.trim().isNotEmpty) ...[
              SizedBox(width: scope.isPhone ? 6 : 8),
              websiteSectionSlot(
                context,
                presenters,
                WebsiteInlineTextSlot(
                  id: 'stats.metric.$index.suffix',
                  value: suffix,
                  valueKeys: const <String>['suffix'],
                  baseStyle: scope.heading(
                    suffixSize,
                    height: 1,
                    color: scope.colors.eyebrow,
                  ),
                  formatting: websiteSectionFormatting(
                    metric['suffixFormatting'],
                  ),
                  formattingKeys: const <String>['suffixFormatting'],
                  placeholder: '+',
                  displayTransform: (value) => value.trim(),
                  repeaterTarget: target,
                ),
              ),
            ],
          ],
        ),
        if (label.trim().isNotEmpty) ...[
          SizedBox(height: scope.isPhone ? 10 : 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: websiteSectionSlot(
              context,
              presenters,
              WebsiteInlineTextSlot(
                id: 'stats.metric.$index.label',
                value: label,
                valueKeys: const <String>['label'],
                baseStyle: scope.body(
                  scope.isPhone ? 14 : 16,
                  height: scope.isPhone ? 1.4 : 1.45,
                  weight: FontWeight.w500,
                  color: scope.colors.muted,
                ),
                formatting: websiteSectionFormatting(
                  metric['labelFormatting'],
                ),
                formattingKeys: const <String>['labelFormatting'],
                placeholder: 'Etiqueta',
                displayTransform: (value) => value.trim(),
                repeaterTarget: target,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
