import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vinabike_public_core/modules/website/models/website_route_content.dart';

// The store's own neutrals (`--ink`, `--muted`, `--line`… in the HTML), so
// the canvas and the published page read the same.
const _ink = Color(0xFF1E293B);
const _onVariant = Color(0xFF475569);
const _muted = Color(0xFF5B6B7F);
const _line = Color(0xFFE2E8F0);
const _outlineVariant = Color(0xFFCBD5E1);
const _mapGround = Color(0xFF0F2036);
const _mapName = Color(0xFF8EA3BB);
const _mapSub = Color(0xFFC9D4E0);
const _otherWay = Color(0xFF9FB3C8);

/// Shared visitor content for the «Ruta» block (2026-11-17): the reader
/// picks where they leave from, reads that way's facts beside the map, then
/// its height profile and its points. The HTML storefront draws the same
/// (`RouteBlockView`); every figure and every mark comes from
/// [WebsiteRouteContent], so both show the same numbers in the same places.
class WebsiteRouteBlockContent extends StatefulWidget {
  const WebsiteRouteBlockContent({
    super.key,
    required this.data,
    required this.primaryColor,
    required this.accentColor,
    this.headingFont,
    this.bodyFont,
    this.showEmptyHint = false,
    this.interactive = true,
  });

  final Map<String, dynamic> data;
  final Color primaryColor;
  final Color accentColor;
  final String? headingFont;
  final String? bodyFont;

  /// In the editor, a block without a route says what it needs; a visitor
  /// sees nothing.
  final bool showEmptyHint;

  /// Whether the reader can pick a way and follow the profile. Edit keeps
  /// the block inert, so a click selects it; Preview and Public do not.
  final bool interactive;

  @override
  State<WebsiteRouteBlockContent> createState() =>
      _WebsiteRouteBlockContentState();
}

class _WebsiteRouteBlockContentState extends State<WebsiteRouteBlockContent> {
  int _active = 0;
  double? _hoverKm;

  TextStyle _body(double size, {FontWeight? weight, Color color = _ink}) =>
      TextStyle(
        fontFamily: widget.bodyFont,
        fontSize: size,
        height: 1.45,
        fontWeight: weight,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    final content = WebsiteRouteContent.fromData(widget.data);
    final ways = content.drawable;
    if (ways.isEmpty) {
      if (!widget.showEmptyHint) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        child: Text(
          'Escribe en el panel el trazado y el perfil de una salida: el mapa '
          'y el perfil se dibujan con ellos.',
          textAlign: TextAlign.center,
          style: _body(16, color: _muted),
        ),
      );
    }
    final active = _active.clamp(0, ways.length - 1);
    final way = ways[active];
    final drawn = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoColumns = width >= 900;
        final phone = width < 720;
        const column = 800.0;
        final pad = phone ? 16.0 : 24.0;
        final sideInset = math.max(pad, (width - column) / 2);
        final side = Padding(
          padding: EdgeInsets.fromLTRB(
            twoColumns ? sideInset : pad,
            twoColumns ? 48 : 40,
            twoColumns ? 48 : pad,
            twoColumns ? 56 : 40,
          ),
          child: _side(content, ways, active),
        );
        final map = content.map == null
            ? null
            : _RouteMap(
                content: content,
                active: active,
                labelScale: phone ? 1.4 : 1,
                accent: widget.accentColor,
                headingFont: widget.headingFont,
                bodyFont: widget.bodyFont,
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border.symmetric(horizontal: BorderSide(color: _line)),
              ),
              // The side sets the row's height, at least 600 as in the
              // HTML; the map fills the other half. The map measures itself
              // (a LayoutBuilder), so the row cannot ask it for an
              // intrinsic height.
              child: twoColumns
                  ? Stack(
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: map == null ? 0 : 600,
                          ),
                          child: SizedBox(width: width / 2, child: side),
                        ),
                        if (map != null)
                          Positioned(
                            left: width / 2,
                            top: 0,
                            right: 0,
                            bottom: 0,
                            child: map,
                          ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        side,
                        if (map != null)
                          SizedBox(height: phone ? 420 : 460, child: map),
                      ],
                    ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: column + 2 * pad),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(pad, phone ? 48 : 64, pad, 24),
                  child: _body2(content, way, phone),
                ),
              ),
            ),
          ],
        );
      },
    );
    return widget.interactive ? drawn : IgnorePointer(child: drawn);
  }

  Widget _side(
    WebsiteRouteContent content,
    List<WebsiteRouteWay> ways,
    int active,
  ) {
    final way = ways[active];
    final top = way.highest;
    final facts = <(String, String)>[
      if (way.start.isNotEmpty) ('Salida', way.start),
      ('Distancia de ida', '${websiteRouteKm(way.distanceKm)} km'),
      ('Subida acumulada', '≈${websiteRouteGain(way.gainM)} m'),
      if (top != null)
        (
          'Punto más alto',
          '${top.ele.round()} m, en el km ${websiteRouteKm(top.km)}',
        ),
      if (way.road.isNotEmpty) ('Camino', way.road),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ways.length > 1) ...[
          Text(
            content.pickLabel.isEmpty ? 'Desde dónde sales' : content.pickLabel,
            style: _body(14, weight: FontWeight.w600, color: _onVariant),
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: _outlineVariant,
              border: Border.all(color: _outlineVariant),
            ),
            child: Row(
              children: [
                for (final (i, option) in ways.indexed) ...[
                  if (i > 0) const SizedBox(width: 1),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == active,
                      child: Material(
                        color: i == active ? widget.primaryColor : Colors.white,
                        child: InkWell(
                          onTap: () => setState(() {
                            _active = i;
                            _hoverKm = null;
                          }),
                          child: SizedBox(
                            height: 52,
                            child: Center(
                              child: Text(
                                option.label,
                                textAlign: TextAlign.center,
                                style: _body(
                                  16,
                                  weight: FontWeight.w600,
                                  color: i == active ? Colors.white : _ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _ink)),
          ),
          child: Column(
            children: [
              for (final (term, value) in facts)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _line)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(term, style: _body(16, color: _onVariant)),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 7,
                        child: Text(
                          value,
                          style: _body(16, weight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body2(WebsiteRouteContent content, WebsiteRouteWay way, bool phone) {
    final chart = phone
        ? WebsiteRouteChart(
            way,
            width: 600,
            height: 400,
            left: 70,
            right: 16,
            top: 48,
            bottom: 70,
            gridStep: 200,
            tickStep: 10,
          )
        : WebsiteRouteChart(
            way,
            width: 800,
            height: 300,
            left: 56,
            right: 14,
            top: 34,
            bottom: 46,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (content.profileTitle.isNotEmpty) ...[
          Text(
            content.profileTitle,
            style: TextStyle(
              fontFamily: widget.headingFont,
              fontSize: phone ? 30 : 36,
              height: 1.15,
              color: _ink,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (way.summary.isNotEmpty) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(way.summary, style: _body(18, color: _onVariant)),
          ),
          const SizedBox(height: 32),
        ],
        AspectRatio(
          aspectRatio: chart.width / chart.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              double kmAt(Offset local) =>
                  chart.kmAt(local.dx / constraints.maxWidth * chart.width);
              return MouseRegion(
                cursor: SystemMouseCursors.precise,
                onHover: (event) =>
                    setState(() => _hoverKm = kmAt(event.localPosition)),
                onExit: (_) => setState(() => _hoverKm = null),
                child: GestureDetector(
                  onTapDown: (details) =>
                      setState(() => _hoverKm = kmAt(details.localPosition)),
                  onHorizontalDragUpdate: (details) =>
                      setState(() => _hoverKm = kmAt(details.localPosition)),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _RouteChartPainter(
                      chart: chart,
                      phone: phone,
                      hoverKm: _hoverKm,
                      primary: widget.primaryColor,
                      accent: widget.accentColor,
                      bodyFont: widget.bodyFont,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 8,
          spacing: 24,
          children: [
            Text(
              phone
                  ? 'Toca el perfil para ver la altura en cada kilómetro.'
                  : 'Pasa el mouse sobre el perfil para ver la altura en cada '
                      'kilómetro.',
              style: _body(15, color: _muted),
            ),
            if (content.source.isNotEmpty)
              Text(content.source, style: _body(15, color: _muted)),
          ],
        ),
        if (way.points.isNotEmpty) ...[
          const SizedBox(height: 40),
          _points(way, phone),
        ],
      ],
    );
  }

  Widget _points(WebsiteRouteWay way, bool phone) {
    final columns = phone ? 1 : 3;
    final rows = <List<WebsiteRoutePoint>>[
      for (var i = 0; i < way.points.length; i += columns)
        way.points.sublist(i, math.min(i + columns, way.points.length)),
    ];
    Widget cell(WebsiteRoutePoint point, int index) => Padding(
          padding: EdgeInsets.fromLTRB(
            phone || index == 0 ? 0 : 28,
            phone ? 20 : 24,
            phone || index == columns - 1 ? 0 : 28,
            phone ? 20 : 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                websiteRoutePointLabel(way, point),
                style: _body(14, weight: FontWeight.w600, color: _onVariant),
              ),
              const SizedBox(height: 8),
              Text(
                point.title.toUpperCase(),
                style: TextStyle(
                  fontFamily: widget.headingFont,
                  fontSize: 21,
                  height: 1.15,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w500,
                  color: _ink,
                ),
              ),
              if (point.note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(point.note, style: _body(16, color: _onVariant)),
              ],
            ],
          ),
        );
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _ink)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (r, row) in rows.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border:
                    r == 0 ? null : const Border(top: BorderSide(color: _line)),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++)
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: c == 0
                                ? null
                                : const Border(left: BorderSide(color: _line)),
                          ),
                          child: c < row.length
                              ? cell(row[c], c)
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The map: the base image placed under the part of the map the block shows
/// (`WebsiteRouteContent.crop`, letterboxed with more map, never less
/// route), and the ways, names and marks painted over it in map units.
class _RouteMap extends StatelessWidget {
  const _RouteMap({
    required this.content,
    required this.active,
    required this.labelScale,
    required this.accent,
    required this.headingFont,
    required this.bodyFont,
  });

  final WebsiteRouteContent content;
  final int active;

  /// The phone's labels are bigger in map units, as in the HTML.
  final double labelScale;
  final Color accent;
  final String? headingFont;
  final String? bodyFont;

  @override
  Widget build(BuildContext context) {
    final frame = content.map!;
    final crop = content.crop()!;
    return Semantics(
      image: true,
      label: content.mapLabel(active),
      child: ColoredBox(
        color: _mapGround,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final scale = math.min(size.width / crop.w, size.height / crop.h);
            final dx = (size.width - crop.w * scale) / 2 - crop.x * scale;
            final dy = (size.height - crop.h * scale) / 2 - crop.y * scale;
            return ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    left: dx,
                    top: dy,
                    width: WebsiteRouteMapFrame.width * scale,
                    height: frame.height * scale,
                    child: Image.network(
                      frame.image,
                      fit: BoxFit.fill,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RouteMapPainter(
                        content: content,
                        active: active,
                        labelScale: labelScale,
                        scale: scale,
                        offset: Offset(dx, dy),
                        accent: accent,
                        headingFont: headingFont,
                        bodyFont: bodyFont,
                      ),
                    ),
                  ),
                  if (content.credit.isNotEmpty)
                    Positioned(
                      right: 12,
                      bottom: 8,
                      child: Text(
                        content.credit,
                        style: TextStyle(
                          fontFamily: bodyFont,
                          fontSize: 11,
                          color: _mapName,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RouteMapPainter extends CustomPainter {
  _RouteMapPainter({
    required this.content,
    required this.active,
    required this.labelScale,
    required this.scale,
    required this.offset,
    required this.accent,
    required this.headingFont,
    required this.bodyFont,
  });

  final WebsiteRouteContent content;
  final int active;
  final double labelScale;
  final double scale;
  final Offset offset;
  final Color accent;
  final String? headingFont;
  final String? bodyFont;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = content.map!;
    final ways = content.drawable;
    final way = ways[active];
    canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(scale);
    for (final place in content.mapPlaces(active)) {
      final p = frame.project(place.at);
      _text(
        canvas,
        place.water ? place.name : place.name.toUpperCase(),
        Offset(p.x, p.y),
        TextStyle(
          fontFamily: place.water ? bodyFont : headingFont,
          fontSize: (place.water ? 14 : 13) * labelScale,
          fontStyle: place.water ? FontStyle.italic : FontStyle.normal,
          fontWeight: FontWeight.w500,
          letterSpacing: place.water ? 0 : 1.6,
          color: _mapName,
        ),
        anchor: _Anchor.middle,
      );
    }
    for (final other in ways) {
      if (identical(other, way)) continue;
      _dashed(
        canvas,
        _trackPath(frame, other),
        Paint()
          ..color = _otherWay.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.drawPath(
      _trackPath(frame, way),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final key = TextStyle(
      fontFamily: bodyFont,
      fontSize: 15 * labelScale,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );
    final sub = TextStyle(
      fontFamily: bodyFont,
      fontSize: 13 * labelScale,
      fontWeight: FontWeight.w500,
      color: _mapSub,
    );
    for (final mark in content.mapMarks(active)) {
      final at = Offset(mark.x, mark.y);
      final anchor = mark.end ? _Anchor.end : _Anchor.start;
      final lx = mark.end ? mark.x - 16 : mark.x + 16;
      switch (mark.kind) {
        case WebsiteRouteMarkKind.destination:
          canvas
            ..drawCircle(at, 9, Paint()..color = accent)
            ..drawCircle(
              at,
              9,
              Paint()
                ..color = _mapGround
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3,
            );
        case WebsiteRouteMarkKind.start:
          canvas
            ..drawCircle(at, 8, Paint()..color = _mapGround)
            ..drawCircle(
              at,
              8,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3,
            );
        case WebsiteRouteMarkKind.highest:
          canvas.drawPath(
            Path()
              ..moveTo(mark.x, mark.y - 9)
              ..relativeLineTo(8, 13)
              ..relativeLineTo(-16, 0)
              ..close(),
            Paint()..color = Colors.white,
          );
        case WebsiteRouteMarkKind.point:
          canvas.drawCircle(at, 5, Paint()..color = Colors.white);
        case WebsiteRouteMarkKind.otherStart:
          _text(
            canvas,
            mark.title.toUpperCase(),
            Offset(lx, mark.y + 5),
            TextStyle(
              fontFamily: headingFont,
              fontSize: 13 * labelScale,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.6,
              color: _mapName,
            ),
            anchor: anchor,
          );
          continue;
      }
      final destination = mark.kind == WebsiteRouteMarkKind.destination;
      final tx = destination ? mark.x - 20 : lx;
      final ty = destination ? mark.y + 40 : mark.y + 5;
      final tAnchor = destination ? _Anchor.end : anchor;
      _text(canvas, mark.title, Offset(tx, ty), key, anchor: tAnchor);
      if (mark.subtitle.isNotEmpty) {
        _text(canvas, mark.subtitle, Offset(tx, ty + 20), sub, anchor: tAnchor);
      }
    }
    canvas.restore();
  }

  Path _trackPath(WebsiteRouteMapFrame frame, WebsiteRouteWay way) {
    final path = Path();
    for (final (i, at) in way.track.indexed) {
      final p = frame.project(at);
      i == 0 ? path.moveTo(p.x, p.y) : path.lineTo(p.x, p.y);
    }
    return path;
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 5, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 6;
      }
    }
  }

  @override
  bool shouldRepaint(_RouteMapPainter old) =>
      old.content != content ||
      old.active != active ||
      old.labelScale != labelScale ||
      old.scale != scale ||
      old.offset != offset ||
      old.accent != accent;
}

enum _Anchor { start, middle, end }

/// Text placed as SVG places it: [at] is on the baseline, at the start, the
/// middle or the end of the line.
void _text(
  Canvas canvas,
  String text,
  Offset at,
  TextStyle style, {
  _Anchor anchor = _Anchor.start,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final baseline = painter.computeDistanceToActualBaseline(
    TextBaseline.alphabetic,
  );
  final dx = switch (anchor) {
    _Anchor.start => 0.0,
    _Anchor.middle => painter.width / 2,
    _Anchor.end => painter.width,
  };
  painter.paint(canvas, Offset(at.dx - dx, at.dy - baseline));
}

class _RouteChartPainter extends CustomPainter {
  _RouteChartPainter({
    required this.chart,
    required this.phone,
    required this.hoverKm,
    required this.primary,
    required this.accent,
    required this.bodyFont,
  });

  final WebsiteRouteChart chart;
  final bool phone;
  final double? hoverKm;
  final Color primary;
  final Color accent;
  final String? bodyFont;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / chart.width;
    canvas
      ..save()
      ..scale(s);
    final axis = TextStyle(
      fontFamily: bodyFont,
      fontSize: phone ? 22 : 13,
      color: _muted,
    );
    final strong = axis.copyWith(fontWeight: FontWeight.w600, color: _ink);
    final right = chart.width - chart.right;
    if (chart.climb case final climb?) {
      canvas.drawRect(
        Rect.fromLTRB(climb.x0, chart.top, climb.x1, chart.floorY),
        Paint()..color = accent.withValues(alpha: 0.08),
      );
      _text(
        canvas,
        climb.label,
        Offset((climb.x0 + climb.x1) / 2, chart.top + (phone ? 28 : 18)),
        axis.copyWith(
          fontWeight: FontWeight.w600,
          color: Color.lerp(accent, Colors.black, 0.25),
        ),
        anchor: _Anchor.middle,
      );
    }
    final gridPaint = Paint()
      ..color = _line
      ..strokeWidth = 1;
    for (final line in chart.grid) {
      canvas.drawLine(
        Offset(chart.left, line.y),
        Offset(right, line.y),
        gridPaint,
      );
      _text(
        canvas,
        line.label,
        Offset(chart.left - 10, line.y + (phone ? 7 : 4)),
        axis,
        anchor: _Anchor.end,
      );
    }
    canvas.drawLine(
      Offset(chart.left, chart.floorY),
      Offset(right, chart.floorY),
      Paint()
        ..color = _ink
        ..strokeWidth = 1,
    );
    for (final tick in chart.ticks) {
      _text(
        canvas,
        tick.label,
        Offset(tick.x, chart.floorY + (phone ? 36 : 24)),
        axis,
        anchor: _Anchor.middle,
      );
    }
    final points = chart.line;
    if (points.isNotEmpty) {
      final line = Path()..moveTo(points.first.x, points.first.y);
      for (final point in points.skip(1)) {
        line.lineTo(point.x, point.y);
      }
      final area = Path.from(line)
        ..lineTo(points.last.x, chart.floorY)
        ..lineTo(points.first.x, chart.floorY)
        ..close();
      canvas
        ..drawPath(area, Paint()..color = primary.withValues(alpha: 0.08))
        ..drawPath(
          line,
          Paint()
            ..color = primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = phone ? 3 : 2
            ..strokeJoin = StrokeJoin.round,
        );
    }
    // A column names the way's points; the phone, only the highest one by
    // its height and the destination. A letter of these labels is a little
    // over half their size, as in the store's drawing.
    final marks = chart.marks(
      minGap: phone ? 160 : 110,
      charWidth: phone ? 12.2 : 7.2,
      fontSize: phone ? 22 : 13,
      gap: phone ? 16 : 12,
      namePoints: !phone,
      nameHighest: phone,
    );
    for (final mark in marks) {
      _dot(canvas, Offset(mark.x, mark.y), mark.last ? accent : _ink);
      if (mark.label.isEmpty) continue;
      _text(
        canvas,
        mark.label,
        Offset(mark.labelX, mark.labelY),
        strong,
        anchor: switch (mark.anchor) {
          'middle' => _Anchor.middle,
          'end' => _Anchor.end,
          _ => _Anchor.start,
        },
      );
    }
    if (hoverKm case final km?) {
      final x = chart.x(km), y = chart.y(chart.way.eleAt(km));
      canvas.drawLine(
        Offset(x, chart.top),
        Offset(x, chart.floorY),
        Paint()
          ..color = _ink
          ..strokeWidth = 1,
      );
      _dot(canvas, Offset(x, y), accent, radius: phone ? 8 : 6);
      final end = x > chart.left + chart.plotWidth * 0.7;
      _text(
        canvas,
        'km ${websiteRouteKm(km)} · ${chart.way.eleAt(km).round()} m',
        Offset(end ? x - 10 : x + 10, chart.top - (phone ? 18 : 12)),
        strong.copyWith(fontWeight: FontWeight.w700),
        anchor: end ? _Anchor.end : _Anchor.start,
      );
    }
    canvas.restore();
  }

  void _dot(Canvas canvas, Offset at, Color color, {double? radius}) {
    final r = radius ?? (phone ? 7 : 5);
    canvas
      ..drawCircle(at, r, Paint()..color = color)
      ..drawCircle(
        at,
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = phone ? 3 : 2,
      );
  }

  @override
  bool shouldRepaint(_RouteChartPainter old) =>
      old.chart != chart ||
      old.hoverKm != hoverKm ||
      old.primary != primary ||
      old.accent != accent;
}
