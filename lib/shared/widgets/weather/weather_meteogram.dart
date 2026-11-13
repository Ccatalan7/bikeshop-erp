import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/weather_forecast.dart';
import '../../models/weather_outlook.dart';
import '../../themes/vinabike_theme_roles.dart';
import 'weather_glyph.dart';

/// One position of the chart: an instant of the next hours, or a whole day.
@immutable
class MeteogramSlot {
  const MeteogramSlot({
    required this.high,
    this.low,
    this.rain = 0,
    this.axisLabel,
    this.condition,
    this.daylight = true,
    this.night = false,
  });

  /// The temperature of the instant, or the day's maximum.
  final double high;

  /// The day's minimum; null for an instant.
  final double? low;

  /// Millimetres from this position to the next one, or over the day.
  final double rain;
  final String? axisLabel;

  /// The sky drawn above this position; null leaves the space empty.
  final WeatherCondition? condition;
  final bool daylight;

  /// Whether the stretch that starts here is night at the shop.
  final bool night;
}

/// Temperature as a line, rain below it and the sky above, over a row of
/// [slots]: the next hours (instants joined edge to edge) or the next days
/// (one column each, with the maximum and the minimum as two lines).
///
/// One drawing for both, so hours and days read with the same grammar.
class WeatherMeteogram extends StatelessWidget {
  const WeatherMeteogram({
    super.key,
    required this.slots,
    required this.columns,
    required this.rainScale,
    required this.rainFloor,
    required this.semanticLabel,
    this.markEvery = 1,
    this.selected,
    this.onSelected,
  });

  final List<MeteogramSlot> slots;

  /// False joins the slots edge to edge as instants; true gives each its own
  /// column.
  final bool columns;

  /// The millimetres that fill the rain band between two instants.
  final double rainScale;

  /// Below this a slot counts as dry and draws no rain: the same line the
  /// sentence above the chart draws, so the two never disagree.
  final double rainFloor;

  /// What the chart says, for a screen reader.
  final String semanticLabel;

  /// Sky and axis label on every n-th slot.
  final int markEvery;
  final int? selected;
  final ValueChanged<int?>? onSelected;

  static const double _glyph = 20;
  static const double _lineBand = 40;
  static const double _rainBand = 14;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final valueStyle =
        (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.1,
    );
    final axisStyle =
        (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 10,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.1,
    );
    final valueHeight = _measure('0°', valueStyle, textScaler).height;
    final axisHeight = _measure('00', axisStyle, textScaler).height;
    final layout = _MeteogramLayout(
      columns: columns,
      count: slots.length,
      glyphTop: 0,
      lineTop: _glyph + 4 + valueHeight + 3,
      lineBottom: _glyph + 4 + valueHeight + 3 + _lineBand,
      rainTop: _glyph + 4 + (valueHeight + 3) * 2 + _lineBand + 2,
      rainBottom:
          _glyph + 4 + (valueHeight + 3) * 2 + _lineBand + 2 + _rainBand,
      axisTop:
          _glyph + 4 + (valueHeight + 3) * 2 + _lineBand + 2 + _rainBand + 4,
      height: _glyph +
          4 +
          (valueHeight + 3) * 2 +
          _lineBand +
          2 +
          _rainBand +
          4 +
          axisHeight,
    );
    final palette = _MeteogramPalette(
      high: roles?.avatarD ?? theme.colorScheme.tertiary,
      low: roles?.neutral.accent ?? theme.colorScheme.onSurfaceVariant,
      water: roles?.avatarA ?? theme.colorScheme.primary,
      night: theme.colorScheme.surfaceContainer,
      surface: theme.colorScheme.surface,
      guide: theme.colorScheme.outlineVariant,
      glyph: WeatherGlyphColors.of(context),
    );

    return Semantics(
      container: true,
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            int? slotAt(Offset position) {
              if (slots.isEmpty || width <= 0) return null;
              return layout.slotAt(position.dx, width);
            }

            final chart = SizedBox(
              width: width,
              height: layout.height,
              child: CustomPaint(
                painter: _MeteogramPainter(
                  slots: slots,
                  layout: layout,
                  palette: palette,
                  rainScale: rainScale,
                  rainFloor: rainFloor,
                  markEvery: markEvery,
                  selected: selected,
                  valueStyle: valueStyle,
                  axisStyle: axisStyle,
                  lowStyle: valueStyle.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  rainStyle: axisStyle.copyWith(
                    color: palette.water,
                    fontWeight: FontWeight.w700,
                  ),
                  textScaler: textScaler,
                ),
              ),
            );
            final select = onSelected;
            if (select == null) return chart;
            return MouseRegion(
              onHover: (event) => select(slotAt(event.localPosition)),
              onExit: (_) => select(null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final slot = slotAt(details.localPosition);
                  select(slot == selected ? null : slot);
                },
                onHorizontalDragStart: (details) =>
                    select(slotAt(details.localPosition)),
                onHorizontalDragUpdate: (details) =>
                    select(slotAt(details.localPosition)),
                child: chart,
              ),
            );
          },
        ),
      ),
    );
  }

  static Size _measure(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }
}

@immutable
class _MeteogramLayout {
  const _MeteogramLayout({
    required this.columns,
    required this.count,
    required this.glyphTop,
    required this.lineTop,
    required this.lineBottom,
    required this.rainTop,
    required this.rainBottom,
    required this.axisTop,
    required this.height,
  });

  final bool columns;
  final int count;
  final double glyphTop;
  final double lineTop;
  final double lineBottom;
  final double rainTop;
  final double rainBottom;
  final double axisTop;
  final double height;

  /// Instants keep half a drawing of margin so the first and the last sky are
  /// not cut; columns take the whole width.
  double get inset => columns ? 0 : WeatherMeteogram._glyph / 2 + 2;

  double x(int index, double width) {
    final span = width - inset * 2;
    if (columns) return inset + span * (index + 0.5) / count;
    if (count < 2) return width / 2;
    return inset + span * index / (count - 1);
  }

  int slotAt(double dx, double width) {
    final span = width - inset * 2;
    if (span <= 0 || count == 0) return 0;
    final share = ((dx - inset) / span).clamp(0.0, 1.0);
    final index =
        columns ? (share * count).floor() : (share * (count - 1)).round();
    return index.clamp(0, count - 1);
  }

  @override
  bool operator ==(Object other) =>
      other is _MeteogramLayout &&
      other.columns == columns &&
      other.count == count &&
      other.lineTop == lineTop &&
      other.height == height;

  @override
  int get hashCode => Object.hash(columns, count, lineTop, height);
}

@immutable
class _MeteogramPalette {
  const _MeteogramPalette({
    required this.high,
    required this.low,
    required this.water,
    required this.night,
    required this.surface,
    required this.guide,
    required this.glyph,
  });

  final Color high;
  final Color low;
  final Color water;
  final Color night;
  final Color surface;
  final Color guide;
  final WeatherGlyphColors glyph;

  @override
  bool operator ==(Object other) =>
      other is _MeteogramPalette &&
      other.high == high &&
      other.low == low &&
      other.water == water &&
      other.night == night &&
      other.surface == surface &&
      other.guide == guide &&
      other.glyph == glyph;

  @override
  int get hashCode =>
      Object.hash(high, low, water, night, surface, guide, glyph);
}

class _MeteogramPainter extends CustomPainter {
  _MeteogramPainter({
    required this.slots,
    required this.layout,
    required this.palette,
    required this.rainScale,
    required this.rainFloor,
    required this.markEvery,
    required this.selected,
    required this.valueStyle,
    required this.lowStyle,
    required this.axisStyle,
    required this.rainStyle,
    required this.textScaler,
  });

  final List<MeteogramSlot> slots;
  final _MeteogramLayout layout;
  final _MeteogramPalette palette;
  final double rainScale;
  final double rainFloor;
  final int markEvery;
  final int? selected;
  final TextStyle valueStyle;
  final TextStyle lowStyle;
  final TextStyle axisStyle;
  final TextStyle rainStyle;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.isEmpty) return;
    final width = size.width;
    final xs = [
      for (var index = 0; index < slots.length; index++) layout.x(index, width),
    ];

    // One scale for both lines. A flat day still gets four degrees of height,
    // so half a degree does not look like a mountain.
    var lowest = double.infinity;
    var highest = -double.infinity;
    for (final slot in slots) {
      lowest = math.min(lowest, slot.low ?? slot.high);
      highest = math.max(highest, slot.high);
    }
    if (highest - lowest < 4) {
      final middle = (highest + lowest) / 2;
      lowest = middle - 2;
      highest = middle + 2;
    }
    double y(double value) =>
        layout.lineTop +
        (highest - value) /
            (highest - lowest) *
            (layout.lineBottom - layout.lineTop);

    _paintNight(canvas, xs);
    _paintSelection(canvas, xs, width);
    _paintRain(canvas, xs, width);

    final highs = [
      for (var index = 0; index < slots.length; index++)
        Offset(xs[index], y(slots[index].high)),
    ];
    final lows = layout.columns
        ? [
            for (var index = 0; index < slots.length; index++)
              Offset(xs[index], y(slots[index].low ?? slots[index].high)),
          ]
        : const <Offset>[];
    if (lows.isNotEmpty) _paintLine(canvas, lows, palette.low);
    _paintLine(canvas, highs, palette.high);

    if (layout.columns) {
      for (var index = 0; index < slots.length; index++) {
        _dot(canvas, lows[index], palette.low);
        _dot(canvas, highs[index], palette.high);
        _label(
          canvas,
          weatherDegrees(slots[index].high),
          valueStyle,
          Offset(xs[index], highs[index].dy - 6),
          width,
          above: true,
        );
        _label(
          canvas,
          weatherDegrees(slots[index].low ?? slots[index].high),
          lowStyle,
          Offset(xs[index], lows[index].dy + 6),
          width,
          above: false,
        );
      }
    } else {
      // The two ends of the day: its maximum and its minimum.
      var top = 0;
      var bottom = 0;
      for (var index = 1; index < slots.length; index++) {
        if (slots[index].high > slots[top].high) top = index;
        if (slots[index].high < slots[bottom].high) bottom = index;
      }
      _dot(canvas, highs.first, palette.high, filled: true);
      if (top != 0) _dot(canvas, highs[top], palette.high);
      _label(
        canvas,
        weatherDegrees(slots[top].high),
        valueStyle,
        Offset(xs[top], highs[top].dy - 6),
        width,
        above: true,
      );
      if (bottom != top) {
        if (bottom != 0) _dot(canvas, highs[bottom], palette.high);
        _label(
          canvas,
          weatherDegrees(slots[bottom].high),
          valueStyle,
          Offset(xs[bottom], highs[bottom].dy + 6),
          width,
          above: false,
        );
      }
      final chosen = selected;
      if (chosen != null && chosen >= 0 && chosen < slots.length) {
        _dot(canvas, highs[chosen], palette.high, filled: true, radius: 3.5);
      }
    }

    for (var index = 0; index < slots.length; index++) {
      if (index % markEvery != 0) continue;
      final slot = slots[index];
      final condition = slot.condition;
      if (condition != null) {
        paintWeatherGlyph(
          canvas,
          Rect.fromCenter(
            center: Offset(
              xs[index],
              layout.glyphTop + WeatherMeteogram._glyph / 2,
            ),
            width: WeatherMeteogram._glyph,
            height: WeatherMeteogram._glyph,
          ),
          condition: condition,
          daylight: slot.daylight,
          colors: palette.glyph,
        );
      }
      final axis = slot.axisLabel;
      if (axis != null) {
        _label(
          canvas,
          axis,
          axisStyle,
          Offset(xs[index], layout.axisTop),
          width,
          above: false,
        );
      }
    }
  }

  void _paintNight(Canvas canvas, List<double> xs) {
    if (layout.columns) return;
    final paint = Paint()..color = palette.night;
    var index = 0;
    while (index < slots.length - 1) {
      if (!slots[index].night) {
        index++;
        continue;
      }
      var end = index;
      while (end < slots.length - 1 && slots[end].night) {
        end++;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            xs[index],
            layout.lineTop - 4,
            xs[end],
            layout.rainBottom,
          ),
          const Radius.circular(4),
        ),
        paint,
      );
      index = end;
    }
  }

  void _paintSelection(Canvas canvas, List<double> xs, double width) {
    final chosen = selected;
    if (chosen == null || chosen < 0 || chosen >= slots.length) return;
    if (layout.columns) {
      final half = width / slots.length / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            xs[chosen] - half + 1,
            layout.glyphTop - 2,
            xs[chosen] + half - 1,
            layout.height,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = palette.night,
      );
      return;
    }
    canvas.drawLine(
      Offset(xs[chosen], layout.lineTop - 4),
      Offset(xs[chosen], layout.rainBottom),
      Paint()
        ..color = palette.guide
        ..strokeWidth = 1,
    );
  }

  void _paintRain(Canvas canvas, List<double> xs, double width) {
    if (layout.columns) {
      for (var index = 0; index < slots.length; index++) {
        final rain = slots[index].rain;
        if (rain < rainFloor) continue;
        _label(
          canvas,
          rain < 1 ? '<1 mm' : '${rain.round()} mm',
          rainStyle,
          Offset(xs[index], layout.rainTop + 1),
          width,
          above: false,
        );
      }
      return;
    }
    final paint = Paint()..color = palette.water;
    final band = layout.rainBottom - layout.rainTop;
    for (var index = 0; index < slots.length - 1; index++) {
      final rain = slots[index].rain;
      if (rain < rainFloor) continue;
      final height = math.max(2.0, math.min(1.0, rain / rainScale) * band);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(
            xs[index] + 0.75,
            layout.rainBottom - height,
            xs[index + 1] - 0.75,
            layout.rainBottom,
          ),
          topLeft: const Radius.circular(1.5),
          topRight: const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  void _paintLine(Canvas canvas, List<Offset> points, Color color) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final before = points[index == 0 ? 0 : index - 1];
      final from = points[index];
      final to = points[index + 1];
      final after = points[index + 2 < points.length ? index + 2 : index + 1];
      final first = from + (to - before) / 6;
      final second = to - (after - from) / 6;
      path.cubicTo(first.dx, first.dy, second.dx, second.dy, to.dx, to.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _dot(
    Canvas canvas,
    Offset centre,
    Color color, {
    bool filled = false,
    double radius = 3,
  }) {
    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = filled ? color : palette.surface,
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  /// Text centred on [anchor]'s x, above or below its y, kept inside the
  /// chart.
  void _label(
    Canvas canvas,
    String text,
    TextStyle style,
    Offset anchor,
    double width, {
    required bool above,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final left = (anchor.dx - painter.width / 2)
        .clamp(0.0, math.max(0.0, width - painter.width))
        .toDouble();
    painter.paint(
      canvas,
      Offset(left, above ? anchor.dy - painter.height : anchor.dy),
    );
    painter.dispose();
  }

  @override
  bool shouldRepaint(_MeteogramPainter oldDelegate) =>
      !identical(oldDelegate.slots, slots) ||
      oldDelegate.layout != layout ||
      oldDelegate.palette != palette ||
      oldDelegate.selected != selected ||
      oldDelegate.rainScale != rainScale ||
      oldDelegate.rainFloor != rainFloor ||
      oldDelegate.markEvery != markEvery ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.valueStyle != valueStyle;
}
