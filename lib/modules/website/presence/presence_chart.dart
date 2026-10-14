import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import 'presence_controller.dart';
import 'presence_models.dart';

final _number = NumberFormat.decimalPattern('es_CL');
final _decimal = NumberFormat('#,##0.0', 'es_CL');

String presenceValue(PresenceMetric metric, double value) => switch (metric) {
      PresenceMetric.position => _decimal.format(value.abs()),
      _ => _number.format(value.round()),
    };

/// The day-by-day line of one metric with what we changed marked under it,
/// so a jump can be read next to its cause.
class PresenceTrendChart extends StatelessWidget {
  const PresenceTrendChart({
    super.key,
    required this.metric,
    required this.series,
    required this.notes,
    required this.onOpenDay,
    this.height = 260,
  });

  final PresenceMetric metric;
  final List<(DateTime, double?)> series;
  final List<PresenceNote> notes;
  final ValueChanged<DateTime> onOpenDay;
  final double height;

  static const double _leftReserved = 46;
  static const double _rightPad = 14;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    if (series.isEmpty || series.every((point) => point.$2 == null)) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            metric == PresenceMetric.visits
                ? 'Sin visitas de Analytics todavía.'
                : 'Sin datos de Search Console en este período.',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
      );
    }

    // Lower is better for the position: drawn negative so better is up.
    final invert = metric == PresenceMetric.position;
    double? value(double? raw) => raw == null ? null : (invert ? -raw : raw);
    final values = [for (final point in series) value(point.$2)];
    final present = values.whereType<double>().toList();
    var minY = present.reduce(math.min);
    var maxY = present.reduce(math.max);
    if (!invert) minY = 0;
    if (maxY == minY) maxY = minY + 1;
    final span = maxY - minY;
    minY = invert ? minY - span * 0.08 : minY;
    maxY = maxY + span * 0.12;

    final smooth = series.length > 45;
    final average = <double?>[];
    for (var i = 0; i < values.length; i++) {
      final window = [
        for (var j = math.max(0, i - 6); j <= i; j++)
          if (values[j] != null) values[j]!,
      ];
      average.add(window.isEmpty
          ? null
          : window.reduce((a, b) => a + b) / window.length);
    }

    final noteDays = <int, List<PresenceNote>>{};
    final first = series.first.$1;
    for (final note in notes) {
      final index = note.day.difference(first).inDays;
      if (index >= 0 && index < series.length) {
        noteDays.putIfAbsent(index, () => []).add(note);
      }
    }

    final line =
        metric == PresenceMetric.visits ? roles.success.accent : scheme.primary;
    final changeColor = roles.warning.accent;
    final analysisColor = roles.info.accent;
    Color markerColor(List<PresenceNote> day) =>
        day.any((n) => n.kind == PresenceNoteKind.change)
            ? changeColor
            : analysisColor;

    final labelEvery = math.max(1, (series.length / 5).ceil());
    final dateLabel =
        DateFormat(series.length > 120 ? 'MMM yy' : 'd MMM', 'es');
    final yInterval = _niceInterval(maxY - minY);

    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: (series.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.7),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: _leftReserved,
              interval: yInterval,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min && invert) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    presenceValue(metric, value),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index != value ||
                    index % labelEvery != 0 ||
                    index >= series.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    dateLabel.format(series[index].$1),
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          verticalLines: [
            for (final entry in noteDays.entries)
              VerticalLine(
                x: entry.key.toDouble(),
                color: markerColor(entry.value).withValues(alpha: 0.45),
                strokeWidth: 1,
                dashArray: const [3, 4],
              ),
          ],
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: scheme.inverseSurface,
            tooltipRoundedRadius: 8,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                spot.barIndex == (smooth ? 1 : 0)
                    ? LineTooltipItem(
                        '${DateFormat('EEE d MMM', 'es').format(series[spot.x.round()].$1)}\n',
                        theme.textTheme.labelSmall!.copyWith(
                          color:
                              scheme.onInverseSurface.withValues(alpha: 0.75),
                        ),
                        children: [
                          TextSpan(
                            text: values[spot.x.round()] == null
                                ? 'sin dato'
                                : '${metric.label}: ${presenceValue(metric, values[spot.x.round()]!)}',
                            style: theme.textTheme.labelMedium!.copyWith(
                              color: scheme.onInverseSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (smooth && average[spot.x.round()] != null)
                            TextSpan(
                              text:
                                  '\nPromedio 7 días: ${presenceValue(metric, average[spot.x.round()]!)}',
                              style: theme.textTheme.labelSmall!.copyWith(
                                color: scheme.onInverseSurface
                                    .withValues(alpha: 0.85),
                              ),
                            ),
                          if (noteDays[spot.x.round()] != null)
                            TextSpan(
                              text:
                                  '\n${_notesLine(noteDays[spot.x.round()]!)}',
                              style: theme.textTheme.labelSmall!.copyWith(
                                color: scheme.onInverseSurface
                                    .withValues(alpha: 0.85),
                              ),
                            ),
                        ],
                      )
                    : null,
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                values[i] == null
                    ? FlSpot.nullSpot
                    : FlSpot(i.toDouble(), values[i]!),
            ],
            isCurved: !smooth,
            curveSmoothness: 0.18,
            preventCurveOverShooting: true,
            color: smooth ? line.withValues(alpha: 0.28) : line,
            barWidth: smooth ? 1.2 : 2.4,
            dotData: FlDotData(show: series.length <= 14),
            belowBarData: BarAreaData(
              show: !invert && !smooth,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  line.withValues(alpha: 0.18),
                  line.withValues(alpha: 0.0)
                ],
              ),
            ),
          ),
          if (smooth)
            LineChartBarData(
              spots: [
                for (var i = 0; i < average.length; i++)
                  average[i] == null
                      ? FlSpot.nullSpot
                      : FlSpot(i.toDouble(), average[i]!),
              ],
              isCurved: true,
              curveSmoothness: 0.2,
              preventCurveOverShooting: true,
              color: line,
              barWidth: 2.4,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: !invert,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    line.withValues(alpha: 0.16),
                    line.withValues(alpha: 0.0)
                  ],
                ),
              ),
            ),
        ],
      ),
      duration: const Duration(milliseconds: 250),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final plotWidth = constraints.maxWidth - _leftReserved - _rightPad;
        double xOf(int index) =>
            _leftReserved +
            (series.length == 1 ? 0 : index / (series.length - 1)) * plotWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.only(right: _rightPad, top: 6),
                child: chart,
              ),
            ),
            if (noteDays.isNotEmpty)
              SizedBox(
                height: 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final entry in noteDays.entries)
                      Positioned(
                        left: xOf(entry.key) - 11,
                        top: 0,
                        width: 22,
                        height: 22,
                        child: Tooltip(
                          message:
                              '${DateFormat('d MMM', 'es').format(series[entry.key].$1)} · ${_notesLine(entry.value)}',
                          child: Semantics(
                            button: true,
                            label:
                                'Cambios del ${DateFormat('d MMMM', 'es').format(series[entry.key].$1)}',
                            child: InkResponse(
                              radius: 16,
                              onTap: () => onOpenDay(series[entry.key].$1),
                              child: Center(
                                child: _Marker(
                                  color: markerColor(entry.value),
                                  count: entry.value.length,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  static String _notesLine(List<PresenceNote> notes) {
    final changes =
        notes.where((n) => n.kind == PresenceNoteKind.change).length;
    final analyses = notes.length - changes;
    return [
      if (changes > 0) changes == 1 ? '1 cambio' : '$changes cambios',
      if (analyses > 0) analyses == 1 ? '1 análisis' : '$analyses análisis',
    ].join(' · ');
  }

  static double _niceInterval(double span) {
    if (span <= 0) return 1;
    final raw = span / 4;
    final magnitude =
        math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final normalized = raw / magnitude;
    final nice = normalized <= 1
        ? 1
        : normalized <= 2
            ? 2
            : normalized <= 2.5
                ? 2.5
                : normalized <= 5
                    ? 5
                    : 10;
    return nice * magnitude;
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.color, required this.count});

  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    final size = count > 1 ? 12.0 : 9.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border:
            Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
      ),
    );
  }
}

/// A small line of the period for a figure tile.
class PresenceSparkline extends StatelessWidget {
  const PresenceSparkline(
      {super.key, required this.values, required this.color});

  final List<double?> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final present = values.whereType<double>();
    if (present.length < 2) return const SizedBox.shrink();
    final min = present.reduce(math.min);
    final max = present.reduce(math.max);
    return LineChart(
      LineChartData(
        minY: min,
        maxY: max == min ? min + 1 : max,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                values[i] == null
                    ? FlSpot.nullSpot
                    : FlSpot(i.toDouble(), values[i]!),
            ],
            isCurved: true,
            curveSmoothness: 0.2,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 1.6,
            dotData: const FlDotData(show: false),
            belowBarData:
                BarAreaData(show: true, color: color.withValues(alpha: 0.10)),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
