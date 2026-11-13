import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../models/weather_forecast.dart';
import '../../models/weather_outlook.dart';
import '../../themes/vinabike_theme_roles.dart';
import 'weather_glyph.dart';

/// The next hours, one column each, read left to right: the hour, the sky,
/// the temperature on its curve, the rain that falls in that hour and the
/// wind with where it blows to.
///
/// Every hour carries its own numbers, as the forecasts people read every day
/// do. It is wider than the panel on purpose: the first hours are in view and
/// the rest come by dragging, by the trackpad or with the two arrows.
class WeatherHourStrip extends StatefulWidget {
  const WeatherHourStrip({
    super.key,
    required this.hours,
    required this.zone,
    this.measured,
  });

  /// One entry per hour, the first being the hour «now» falls in.
  final List<WeatherHour> hours;
  final WeatherZone zone;

  /// What was just measured: the first column shows it instead of the
  /// forecast for the same hour, so it never contradicts «now».
  final WeatherMoment? measured;

  @override
  State<WeatherHourStrip> createState() => _WeatherHourStripState();
}

class _WeatherHourStripState extends State<WeatherHourStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target =
        (position.pixels + direction * position.viewportDimension * 0.8)
            .clamp(0.0, position.maxScrollExtent);
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = widget.hours;
    if (hours.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final faint = roles?.faintForeground ?? muted;
    final water = roles?.avatarA ?? theme.colorScheme.primary;
    final measured =
        widget.measured?.measurement == null ? null : widget.measured;

    final base = theme.textTheme.labelSmall ?? const TextStyle();
    final hourStyle = base.copyWith(
      color: muted,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.2,
    );
    final valueStyle = (theme.textTheme.labelLarge ?? base).copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.2,
    );
    final smallStyle = hourStyle.copyWith(color: theme.colorScheme.onSurface);
    final captionStyle =
        base.copyWith(color: faint, fontWeight: FontWeight.w600);

    // What each column shows. The first one is «now» as it was measured.
    final cells = <_Cell>[
      for (final (index, hour) in hours.indexed)
        index == 0 && measured != null
            ? _Cell(
                hour: hour,
                local: widget.zone.local(hour.time),
                temperature: measured.temperature,
                condition: measured.condition ?? hour.condition,
                wind: measured.windKilometresPerHour ??
                    hour.windKilometresPerHour,
                windFrom: measured.windKilometresPerHour == null
                    ? hour.windFromDirection
                    : measured.windFromDirection,
                humidity: measured.humidity ?? hour.humidity,
              )
            : _Cell(
                hour: hour,
                local: widget.zone.local(hour.time),
                temperature: hour.temperature,
                condition: hour.condition,
                wind: hour.windKilometresPerHour,
                windFrom: hour.windFromDirection,
                humidity: hour.humidity,
              ),
    ];

    var rain = 0.0;
    var peak = 0.0;
    double? strongest;
    for (final cell in cells) {
      if (cell.wet) {
        rain += cell.hour.precipitation;
        peak = math.max(peak, cell.hour.precipitation);
      }
      final wind = cell.wind;
      if (wind != null) strongest = math.max(strongest ?? 0, wind);
    }
    // Only the forecast's hours count: «now» alone is not a forecast.
    final windy = cells.skip(1).any((cell) => cell.wind != null);
    final humid = cells.any((cell) => cell.humidity != null);

    final hourHeight = _height('00', hourStyle, scaler);
    final valueHeight = _height('0°', valueStyle, scaler);
    final smallHeight = _height('0', smallStyle, scaler);
    final captionHeight = _height('Lluvia', captionStyle, scaler);
    const glyph = 22.0;
    const curve = 38.0;
    const bars = 30.0;
    const arrow = 16.0;

    var y = 0.0;
    final hourTop = y;
    y += hourHeight + 6;
    final glyphTop = y;
    y += glyph + 6;
    final valueTop = y;
    y += valueHeight + 4;
    final curveTop = y;
    y += curve + 12;
    final rainCaptionTop = y;
    y += captionHeight + 4;
    final rainTop = y;
    // A dry stretch needs no room for bars: the caption says it.
    if (rain > 0) y += smallHeight + 2 + bars;
    y += 10;
    final windCaptionTop = y;
    y += captionHeight + 4;
    final windTop = y;
    if (windy) y += arrow + 2 + smallHeight;
    y += 10;
    final humidityCaptionTop = y;
    if (humid) y += captionHeight + 4;
    final humidityTop = y;
    if (humid) y += smallHeight;
    final height = y;

    final layout = _StripLayout(
      column: scaler.scale(44).clamp(40.0, 64.0),
      hourTop: hourTop,
      glyphTop: glyphTop,
      valueTop: valueTop,
      curveTop: curveTop,
      curveBottom: curveTop + curve,
      rainTop: rainTop,
      rainBars: rain > 0 ? bars : 0,
      windTop: windy ? windTop : null,
      humidityTop: humidityTop,
      height: height,
    );

    Widget caption(double top, String name, String detail) => Positioned(
          left: 0,
          right: 0,
          top: top,
          child: ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: name),
                  TextSpan(
                    text: '  $detail',
                    style: const TextStyle(fontWeight: FontWeight.w400),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: captionStyle,
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                container: true,
                header: true,
                child: Text(
                  'Próximas ${cells.length} horas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            _PageButton(
              tooltip: 'Horas anteriores',
              icon: Icons.chevron_left_rounded,
              onPressed: () => _page(-1),
            ),
            _PageButton(
              tooltip: 'Horas siguientes',
              icon: Icons.chevron_right_rounded,
              onPressed: () => _page(1),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: ScrollConfiguration(
                  // A mouse drags it too: its wheel only scrolls the panel.
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: PointerDeviceKind.values.toSet(),
                    scrollbars: false,
                  ),
                  child: SingleChildScrollView(
                    key: const ValueKey<String>('weather-hour-strip'),
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    child: CustomPaint(
                      painter: _StripPainter(
                        cells: cells,
                        layout: layout,
                        rainScale: math.max(2, peak),
                        line: roles?.avatarD ?? theme.colorScheme.tertiary,
                        surface: theme.colorScheme.surface,
                        water: water,
                        ink: theme.colorScheme.onSurface,
                        muted: muted,
                        hairline:
                            roles?.hairline ?? theme.colorScheme.outlineVariant,
                        glyph: WeatherGlyphColors.of(context),
                        hourStyle: hourStyle,
                        valueStyle: valueStyle,
                        smallStyle: smallStyle,
                        rainStyle: smallStyle.copyWith(
                          color: water,
                          fontWeight: FontWeight.w700,
                        ),
                        scaler: scaler,
                      ),
                      child: Row(
                        children: [
                          for (final (index, cell) in cells.indexed)
                            SizedBox(
                              width: layout.column,
                              height: height,
                              child: Semantics(
                                container: true,
                                label: cell.spoken(now: index == 0),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              caption(
                rainCaptionTop,
                'Lluvia',
                rain > 0
                    ? '${weatherRainAmount(rain)} mm en estas horas'
                    : 'sin lluvia en estas horas',
              ),
              caption(
                windCaptionTop,
                'Viento',
                windy
                    ? 'hasta ${strongest!.round()} km/h'
                    : 'sin pronóstico confiable por hora en este lugar',
              ),
              if (humid) caption(humidityCaptionTop, 'Humedad', '%'),
            ],
          ),
        ),
      ],
    );
  }

  static double _height(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}

@immutable
class _Cell {
  const _Cell({
    required this.hour,
    required this.local,
    required this.temperature,
    required this.condition,
    required this.wind,
    required this.windFrom,
    required this.humidity,
  });

  final WeatherHour hour;

  /// [hour] on the place's clock.
  final DateTime local;
  final double temperature;
  final WeatherCondition? condition;

  /// Kilometres per hour.
  final double? wind;
  final double? windFrom;

  /// Per cent.
  final double? humidity;

  bool get wet => hour.precipitation >= WeatherOutlook.rainPerHour;

  String spoken({required bool now}) {
    final speed = wind;
    final from = windFrom;
    final humidity = this.humidity;
    return [
      now ? 'Ahora' : 'A las ${local.hour}:00',
      weatherDegrees(temperature),
      if (condition != null) condition!.label.toLowerCase(),
      wet ? 'lluvia ${weatherRainAmount(hour.precipitation)} mm' : 'sin lluvia',
      if (speed != null)
        speed < 2
            ? 'sin viento'
            : 'viento${from == null ? '' : ' del ${weatherCompassWords(from)}'} '
                'a ${speed.round()} km/h',
      if (humidity != null) 'humedad ${humidity.round()} %',
    ].join(', ');
  }
}

@immutable
class _StripLayout {
  const _StripLayout({
    required this.column,
    required this.hourTop,
    required this.glyphTop,
    required this.valueTop,
    required this.curveTop,
    required this.curveBottom,
    required this.rainTop,
    required this.rainBars,
    required this.windTop,
    required this.humidityTop,
    required this.height,
  });

  final double column;
  final double hourTop;
  final double glyphTop;
  final double valueTop;
  final double curveTop;
  final double curveBottom;
  final double rainTop;

  /// Height of the tallest bar; zero when nothing falls.
  final double rainBars;

  /// Null when no hour has a wind to draw.
  final double? windTop;
  final double humidityTop;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is _StripLayout &&
      other.column == column &&
      other.curveTop == curveTop &&
      other.rainBars == rainBars &&
      other.windTop == windTop &&
      other.height == height;

  @override
  int get hashCode => Object.hash(column, curveTop, rainBars, windTop, height);
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.cells,
    required this.layout,
    required this.rainScale,
    required this.line,
    required this.surface,
    required this.water,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.glyph,
    required this.hourStyle,
    required this.valueStyle,
    required this.smallStyle,
    required this.rainStyle,
    required this.scaler,
  });

  final List<_Cell> cells;
  final _StripLayout layout;
  final double rainScale;
  final Color line;
  final Color surface;
  final Color water;
  final Color ink;
  final Color muted;
  final Color hairline;
  final WeatherGlyphColors glyph;
  final TextStyle hourStyle;
  final TextStyle valueStyle;
  final TextStyle smallStyle;
  final TextStyle rainStyle;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    final column = layout.column;
    double centre(int index) => column * (index + 0.5);

    // A flat stretch still gets four degrees of height, so half a degree does
    // not look like a mountain.
    var lowest = double.infinity;
    var highest = -double.infinity;
    for (final cell in cells) {
      lowest = math.min(lowest, cell.temperature);
      highest = math.max(highest, cell.temperature);
    }
    if (highest - lowest < 4) {
      final middle = (highest + lowest) / 2;
      lowest = middle - 2;
      highest = middle + 2;
    }
    double level(double value) =>
        layout.curveTop +
        6 +
        (highest - value) /
            (highest - lowest) *
            (layout.curveBottom - layout.curveTop - 12);

    final points = [
      for (final (index, cell) in cells.indexed)
        Offset(centre(index), level(cell.temperature)),
    ];
    _curve(canvas, points);

    final windTop = layout.windTop;
    for (final (index, cell) in cells.indexed) {
      final x = centre(index);
      final midnight = index > 0 && cell.local.hour == 0;
      if (midnight) {
        // Where the next day starts.
        canvas.drawLine(
          Offset(column * index, layout.hourTop),
          Offset(column * index, layout.curveBottom),
          Paint()
            ..color = hairline
            ..strokeWidth = 1,
        );
      }
      _text(
        canvas,
        index == 0
            ? 'Ahora'
            : midnight
                ? weatherWeekdayShort(cell.local)
                : '${cell.local.hour}',
        index == 0 || midnight
            ? hourStyle.copyWith(color: ink, fontWeight: FontWeight.w700)
            : hourStyle,
        Offset(x, layout.hourTop),
      );
      final condition = cell.condition;
      if (condition != null) {
        paintWeatherGlyph(
          canvas,
          Rect.fromLTWH(x - 11, layout.glyphTop, 22, 22),
          condition: condition,
          daylight: cell.hour.daylight,
          colors: glyph,
        );
      }
      _text(
        canvas,
        weatherDegrees(cell.temperature),
        valueStyle,
        Offset(x, layout.valueTop),
      );
      canvas.drawCircle(points[index], 3, Paint()..color = surface);
      canvas.drawCircle(
        points[index],
        3,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );

      if (layout.rainBars > 0 && cell.wet) {
        final label =
            _measure(weatherRainAmount(cell.hour.precipitation), rainStyle);
        final bar = math.max(
          3.0,
          math.min(1.0, cell.hour.precipitation / rainScale) * layout.rainBars,
        );
        final bottom = layout.rainTop + label.height + 2 + layout.rainBars;
        label.paint(
          canvas,
          Offset(x - label.width / 2, bottom - bar - 2 - label.height),
        );
        label.dispose();
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(
              x - column * 0.3,
              bottom - bar,
              x + column * 0.3,
              bottom,
            ),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          Paint()..color = water,
        );
      }

      final wind = cell.wind;
      if (windTop != null && wind != null) {
        final from = cell.windFrom;
        if (wind >= 2 && from != null) {
          _arrow(canvas, Offset(x, windTop + 8), from);
        }
        _text(canvas, '${wind.round()}', smallStyle, Offset(x, windTop + 18));
      }
      final humidity = cell.humidity;
      if (humidity != null) {
        _text(
          canvas,
          '${humidity.round()}',
          hourStyle,
          Offset(x, layout.humidityTop),
        );
      }
    }
  }

  void _curve(Canvas canvas, List<Offset> points) {
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
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// An arrow that flies with the wind: it points where it blows to.
  void _arrow(Canvas canvas, Offset centre, double fromDegrees) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate((fromDegrees + 180) * math.pi / 180);
    final path = Path()
      ..moveTo(0, -7)
      ..lineTo(5, 6)
      ..lineTo(0, 3)
      ..lineTo(-5, 6)
      ..close();
    canvas.drawPath(path, Paint()..color = muted);
    canvas.restore();
  }

  TextPainter _measure(String text, TextStyle style) => TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();

  /// Text centred on [top]'s x, starting at its y.
  void _text(Canvas canvas, String text, TextStyle style, Offset top) {
    final painter = _measure(text, style);
    painter.paint(canvas, Offset(top.dx - painter.width / 2, top.dy));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_StripPainter oldDelegate) =>
      !identical(oldDelegate.cells, cells) ||
      oldDelegate.layout != layout ||
      oldDelegate.rainScale != rainScale ||
      oldDelegate.line != line ||
      oldDelegate.surface != surface ||
      oldDelegate.water != water ||
      oldDelegate.ink != ink ||
      oldDelegate.glyph != glyph ||
      oldDelegate.scaler != scaler;
}
