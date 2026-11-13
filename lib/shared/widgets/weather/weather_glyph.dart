import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/weather_forecast.dart';
import '../../themes/vinabike_theme_roles.dart';

/// The tones a weather drawing is made of, taken from the mounted theme: the
/// sun in the amber identity tone, water in the blue one, clouds and the moon
/// in the neutral. Each has the soft fill the resolver designed for it, so
/// the drawing holds in light and in dark without a single local colour.
@immutable
class WeatherGlyphColors {
  const WeatherGlyphColors({
    required this.sun,
    required this.sunFill,
    required this.cloud,
    required this.cloudFill,
    required this.water,
  });

  factory WeatherGlyphColors.of(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    if (roles == null) {
      // A host without the app theme still draws, in its own scheme.
      final scheme = theme.colorScheme;
      return WeatherGlyphColors(
        sun: scheme.tertiary,
        sunFill: scheme.tertiaryContainer,
        cloud: scheme.onSurfaceVariant,
        cloudFill: scheme.surfaceContainerHighest,
        water: scheme.primary,
      );
    }
    return WeatherGlyphColors(
      sun: roles.avatarD,
      sunFill: roles.avatarSoftD,
      cloud: roles.neutral.accent,
      cloudFill: roles.neutral.container,
      water: roles.avatarA,
    );
  }

  final Color sun;
  final Color sunFill;

  /// Clouds, fog and the moon.
  final Color cloud;
  final Color cloudFill;

  /// Rain, sleet and snow.
  final Color water;

  @override
  bool operator ==(Object other) =>
      other is WeatherGlyphColors &&
      other.sun == sun &&
      other.sunFill == sunFill &&
      other.cloud == cloud &&
      other.cloudFill == cloudFill &&
      other.water == water;

  @override
  int get hashCode => Object.hash(sun, sunFill, cloud, cloudFill, water);
}

/// The sky as a small drawing: sun or moon, cloud, and what falls from it.
///
/// It is composed from the parts of a [WeatherCondition] instead of picked
/// from a set of pictures, so every combination the provider can name has its
/// drawing, and day or night is decided by where the sun is at the shop.
class WeatherGlyph extends StatelessWidget {
  const WeatherGlyph({
    super.key,
    required this.condition,
    required this.daylight,
    this.size = 24,
  });

  final WeatherCondition condition;
  final bool daylight;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _WeatherGlyphPainter(
          condition: condition,
          daylight: daylight,
          colors: WeatherGlyphColors.of(context),
        ),
      ),
    );
  }
}

class _WeatherGlyphPainter extends CustomPainter {
  const _WeatherGlyphPainter({
    required this.condition,
    required this.daylight,
    required this.colors,
  });

  final WeatherCondition condition;
  final bool daylight;
  final WeatherGlyphColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    paintWeatherGlyph(
      canvas,
      Offset.zero & size,
      condition: condition,
      daylight: daylight,
      colors: colors,
    );
  }

  @override
  bool shouldRepaint(_WeatherGlyphPainter oldDelegate) =>
      oldDelegate.condition.code != condition.code ||
      oldDelegate.daylight != daylight ||
      oldDelegate.colors != colors;
}

/// Paints the drawing of [condition] inside [rect]. Shared with the chart,
/// which places several of them on one canvas.
void paintWeatherGlyph(
  Canvas canvas,
  Rect rect, {
  required WeatherCondition condition,
  required bool daylight,
  required WeatherGlyphColors colors,
}) {
  // Drawn on a 24-unit square.
  final unit = rect.shortestSide / 24;
  if (unit <= 0) return;
  canvas.save();
  canvas.translate(rect.left, rect.top);
  canvas.scale(unit);
  // A line never thinner than about 1.3 px, however small the drawing.
  final stroke = (1.3 / unit).clamp(1.5, 2.2).toDouble();
  final pen = _GlyphPen(canvas, colors, stroke);

  final wet = condition.isWet;
  final thunder = condition.thunder;
  if (wet || thunder) {
    if (condition.showers) {
      pen.light(const Offset(16.6, 6.6), 3.1, daylight: daylight, rays: 2.6);
      pen.cloud(const Offset(2.4, 6.4), 1.0);
      pen.fall(condition, top: 18.2);
    } else {
      pen.cloud(const Offset(2.8, 3.4), 1.15);
      pen.fall(condition, top: 16.8);
    }
  } else {
    switch (condition.sky) {
      case WeatherSky.clear:
        pen.light(const Offset(12, 12), daylight ? 4.8 : 7, daylight: daylight);
      case WeatherSky.fair:
        pen.light(const Offset(10.4, 10.4), 4.3, daylight: daylight, rays: 3.4);
        pen.cloud(const Offset(11.2, 13.4), 0.7);
      case WeatherSky.partlyCloudy:
        pen.light(const Offset(16.2, 8.2), 3.5, daylight: daylight, rays: 2.9);
        pen.cloud(const Offset(2.0, 9.4), 1.05);
      case WeatherSky.cloudy:
        pen.cloud(const Offset(1.6, 5.6), 1.3);
      case WeatherSky.fog:
        pen.cloud(const Offset(3.6, 3.2), 1.05);
        pen.line(const Offset(5, 17.4), const Offset(19, 17.4), colors.cloud);
        pen.line(
          const Offset(7.6, 20.8),
          const Offset(16.4, 20.8),
          colors.cloud,
        );
    }
  }
  canvas.restore();
}

class _GlyphPen {
  _GlyphPen(this.canvas, this.colors, this.stroke);

  final Canvas canvas;
  final WeatherGlyphColors colors;
  final double stroke;

  Paint _line(Color color, [double? width]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width ?? stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  Paint _fill(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  void line(Offset from, Offset to, Color color, [double? width]) {
    canvas.drawLine(from, to, _line(color, width));
  }

  /// The sun by day, the moon by night.
  void light(
    Offset centre,
    double radius, {
    required bool daylight,
    double rays = 4.4,
  }) {
    if (!daylight) {
      final moon = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: centre, radius: radius)),
        Path()
          ..addOval(
            Rect.fromCircle(
              center: centre + Offset(radius * 0.48, -radius * 0.36),
              radius: radius * 0.86,
            ),
          ),
      );
      canvas.drawPath(moon, _fill(colors.cloudFill));
      canvas.drawPath(moon, _line(colors.cloud));
      return;
    }
    canvas.drawCircle(centre, radius, _fill(colors.sunFill));
    canvas.drawCircle(centre, radius, _line(colors.sun));
    for (var ray = 0; ray < 8; ray++) {
      final angle = ray * math.pi / 4;
      final direction = Offset(math.cos(angle), math.sin(angle));
      line(
        centre + direction * (radius + 1.9),
        centre + direction * (radius + rays),
        colors.sun,
      );
    }
  }

  /// A cloud 16 units wide and 10 tall at [scale] 1, with its top-left corner
  /// at [origin].
  void cloud(Offset origin, double scale) {
    Rect bump(double x, double y, double radius) => Rect.fromCircle(
          center: origin + Offset(x, y) * scale,
          radius: radius * scale,
        );
    var outline = Path()..addOval(bump(4, 6.5, 3.5));
    outline = Path.combine(
      PathOperation.union,
      outline,
      Path()..addOval(bump(8.5, 4.6, 4.6)),
    );
    outline = Path.combine(
      PathOperation.union,
      outline,
      Path()..addOval(bump(12.5, 6.9, 3.1)),
    );
    outline = Path.combine(
      PathOperation.union,
      outline,
      Path()
        ..addRect(
          Rect.fromPoints(
            origin + const Offset(4, 6.5) * scale,
            origin + const Offset(12.5, 10) * scale,
          ),
        ),
    );
    canvas.drawPath(outline, _fill(colors.cloudFill));
    canvas.drawPath(outline, _line(colors.cloud));
  }

  /// What falls from the cloud, starting at [top].
  void fall(WeatherCondition condition, {required double top}) {
    final heavy = condition.intensity == WeatherIntensity.heavy;
    final light = condition.intensity == WeatherIntensity.light;
    if (condition.thunder) {
      final bolt = Path()
        ..moveTo(12.9, top - 1.4)
        ..lineTo(9.9, top + 2.3)
        ..lineTo(12.0, top + 2.3)
        ..lineTo(11.0, top + 5.2)
        ..lineTo(14.6, top + 0.9)
        ..lineTo(12.5, top + 0.9)
        ..close();
      canvas.drawPath(bolt, _fill(colors.sun));
      canvas.drawPath(bolt, _line(colors.sun, stroke * 0.5));
    }
    final columns = condition.thunder
        ? const [7.2, 17.0]
        : heavy
            ? const [7.2, 10.4, 13.6, 16.8]
            : light
                ? const [9.6, 14.2]
                : const [8.2, 12.0, 15.8];
    for (var index = 0; index < columns.length; index++) {
      final x = columns[index];
      final frozen = condition.precipitation == WeatherPrecipitation.snow ||
          (condition.precipitation == WeatherPrecipitation.sleet &&
              index.isOdd);
      if (condition.precipitation == WeatherPrecipitation.none) continue;
      if (frozen) {
        canvas.drawCircle(Offset(x - 0.4, top + 1.7), 1.0, _fill(colors.water));
      } else {
        line(
          Offset(x, top),
          Offset(x - 1.2, top + 3.2),
          colors.water,
          heavy ? stroke * 1.15 : stroke,
        );
      }
    }
  }
}
