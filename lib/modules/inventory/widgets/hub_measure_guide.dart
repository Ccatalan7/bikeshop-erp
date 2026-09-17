import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Parts of the hub drawing that a spec field can light up.
enum HubGuidePart {
  old,
  flangeToFlange,
  centerToLeft,
  centerToRight,
  pcdLeft,
  pcdRight,
  spokeHoleDiameter,
  spokeHoles,
  axleDiameter,
  axleBody,
  axleEnds,
  rotorMount,
  driveReceiver,
  bearings,
}

/// Which parts of the drawing each hub field points at. A field that has no
/// place on the drawing (position of the package, evidence source, package
/// rows) maps to `null`: the guide keeps its text but nothing lights up.
Set<HubGuidePart>? hubGuidePartsForField(String key) => switch (key) {
      'hub_old_mm' => const {HubGuidePart.old},
      'hub_flange_to_flange_mm' => const {HubGuidePart.flangeToFlange},
      'center_to_flange_left_mm' => const {HubGuidePart.centerToLeft},
      'center_to_flange_right_mm' => const {HubGuidePart.centerToRight},
      'flange_pcd_left_mm' => const {HubGuidePart.pcdLeft},
      'flange_pcd_right_mm' => const {HubGuidePart.pcdRight},
      'spoke_hole_diameter_mm' => const {HubGuidePart.spokeHoleDiameter},
      'spoke_hole_count' => const {HubGuidePart.spokeHoles},
      'hub_spoke_head_interface' => const {HubGuidePart.spokeHoles},
      'hub_axle_diameter_mm' => const {HubGuidePart.axleDiameter},
      'hub_axle_diameter_datum' => const {
          HubGuidePart.axleDiameter,
          HubGuidePart.axleBody
        },
      'hub_axle_mount_kind' => const {HubGuidePart.axleEnds},
      'hub_thru_axle_supplied' => const {HubGuidePart.axleBody},
      'hub_supplied_thru_axle_reference' => const {HubGuidePart.axleBody},
      'hub_rotor_mount_present' => const {HubGuidePart.rotorMount},
      'rotor_mount_type' => const {HubGuidePart.rotorMount},
      'hub_drive_receiver_present' => const {HubGuidePart.driveReceiver},
      'hub_drive_receiver_kind' => const {HubGuidePart.driveReceiver},
      'hub_drive_receiver_reference' => const {HubGuidePart.driveReceiver},
      'bearing_system' => const {HubGuidePart.bearings},
      _ => null,
    };

/// Field keys the drawing can point at, in the order a mechanic measures:
/// width first, then flanges, then holes, then axle, then what is bolted on.
const List<String> hubGuideFieldKeys = [
  'hub_old_mm',
  'hub_flange_to_flange_mm',
  'center_to_flange_left_mm',
  'center_to_flange_right_mm',
  'flange_pcd_left_mm',
  'flange_pcd_right_mm',
  'spoke_hole_count',
  'spoke_hole_diameter_mm',
  'hub_spoke_head_interface',
  'hub_axle_diameter_datum',
  'hub_axle_diameter_mm',
  'hub_axle_mount_kind',
  'hub_thru_axle_supplied',
  'hub_supplied_thru_axle_reference',
  'hub_rotor_mount_present',
  'rotor_mount_type',
  'hub_drive_receiver_present',
  'hub_drive_receiver_kind',
  'hub_drive_receiver_reference',
  'bearing_system',
];

/// The field a tap on a drawn dimension should open. One part can serve
/// several fields (the axle body serves the datum and the thru-axle rows);
/// the first field in [hubGuideFieldKeys] that lights that part wins.
String? hubGuideFieldForPart(HubGuidePart part) {
  for (final key in hubGuideFieldKeys) {
    final parts = hubGuidePartsForField(key);
    if (parts != null && parts.contains(part)) return key;
  }
  return null;
}

/// Technical drawing of a rear disc hub: a section through the axle, with
/// the wheel centre line, and the left flange seen from the front. Every
/// dimension the sheet asks for is drawn where a mechanic would measure it.
///
/// [highlightedKey] is the spec field the operator is on: its parts are drawn
/// in the accent role and every other dimension recedes. Tapping a dimension
/// reports its field through [onFieldTap].
class HubMeasureGuide extends StatefulWidget {
  const HubMeasureGuide({
    super.key,
    this.highlightedKey,
    this.spokeHoleCount,
    this.onFieldTap,
    this.aspectRatio = 1000 / 600,
  });

  final String? highlightedKey;
  final int? spokeHoleCount;
  final ValueChanged<String>? onFieldTap;
  final double aspectRatio;

  @override
  State<HubMeasureGuide> createState() => _HubMeasureGuideState();
}

class _HubMeasureGuideState extends State<HubMeasureGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180), value: 1);
  final _hits = <HubGuidePart, Rect>{};
  Set<HubGuidePart>? _previous;

  @override
  void didUpdateWidget(HubMeasureGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedKey != widget.highlightedKey) {
      _previous = oldWidget.highlightedKey == null
          ? null
          : hubGuidePartsForField(oldWidget.highlightedKey!);
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details) {
    final onFieldTap = widget.onFieldTap;
    if (onFieldTap == null) return;
    for (final entry in _hits.entries) {
      if (entry.value.inflate(6).contains(details.localPosition)) {
        final key = hubGuideFieldForPart(entry.key);
        if (key != null) onFieldTap(key);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final current = widget.highlightedKey == null
        ? null
        : hubGuidePartsForField(widget.highlightedKey!);
    final palette = _GuidePalette(
      ink: scheme.onSurface,
      inkMuted: scheme.onSurfaceVariant,
      hairline: scheme.outlineVariant,
      fill: scheme.surfaceContainerHighest,
      fillDeep: scheme.surfaceContainerHigh,
      paper: scheme.surface,
      accent: scheme.primary,
      accentContainer: scheme.primaryContainer,
      onAccentContainer: scheme.onPrimaryContainer,
    );
    final labelStyle = theme.textTheme.labelSmall ?? const TextStyle();
    return Semantics(
      label: 'Dibujo de la maza con sus medidas',
      image: true,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.onFieldTap == null ? null : _handleTap,
          child: MouseRegion(
            cursor: widget.onFieldTap == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: AnimatedBuilder(
              animation: _fade,
              builder: (context, _) => CustomPaint(
                painter: _HubGuidePainter(
                  palette: palette,
                  labelStyle: labelStyle,
                  current: current,
                  previous: _previous,
                  progress: reduceMotion ? 1 : _fade.value,
                  spokeHoleCount: widget.spokeHoleCount,
                  hits: _hits,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GuidePalette {
  const _GuidePalette({
    required this.ink,
    required this.inkMuted,
    required this.hairline,
    required this.fill,
    required this.fillDeep,
    required this.paper,
    required this.accent,
    required this.accentContainer,
    required this.onAccentContainer,
  });
  final Color ink;
  final Color inkMuted;
  final Color hairline;
  final Color fill;
  final Color fillDeep;
  final Color paper;
  final Color accent;
  final Color accentContainer;
  final Color onAccentContainer;
}

/// Geometry in design units (1000 × 600). The painter scales it uniformly.
class _G {
  static const w = 1000.0;
  static const h = 600.0;

  // Section view: axle axis and wheel centre line.
  static const axisY = 300.0;
  static const centerX = 365.0;

  // Over-locknut faces, axle and end caps.
  static const oldLeft = 158.0;
  static const oldRight = 572.0;
  static const axleR = 16.0;
  static const boreR = 7.0;
  static const axleLeft = 128.0;
  static const axleRight = 604.0;
  static const capW = 24.0;
  static const capR = 34.0;

  // Rotor mount (6 bolts) next to the left cap.
  static const rotorX = 196.0;
  static const rotorW = 12.0;
  static const rotorR = 90.0;
  static const rotorBoltY = 66.0;

  // Flanges: disc side (left) is taller, drive side (right) shorter.
  static const flangeLX = 250.0;
  static const flangeRX = 466.0;
  static const flangeT = 18.0;
  static const pcdL = 214.0;
  static const pcdR = 196.0;
  static const flangeLip = 18.0;
  static const holeR = 8.0;

  // Shell and freehub.
  static const barrelR = 44.0;
  static const freehubRight = 560.0;
  static const freehubR = 38.0;

  // Dimension rows.
  static const ftfY = 92.0;
  static const centerY = 138.0;
  static const oldY = 494.0;
  static const pcdLeftX = 104.0;
  static const pcdRightX = 618.0;
  static const axleDimX = 656.0;

  // End view (left flange seen from the front).
  static const evCx = 852.0;
  static const evCy = 292.0;
  static const evR = 124.0;
  static const evPcd = 108.0;
  static const evBoltR = 44.0;
}

class _HubGuidePainter extends CustomPainter {
  _HubGuidePainter({
    required this.palette,
    required this.labelStyle,
    required this.current,
    required this.previous,
    required this.progress,
    required this.spokeHoleCount,
    required this.hits,
  });

  final _GuidePalette palette;
  final TextStyle labelStyle;
  final Set<HubGuidePart>? current;
  final Set<HubGuidePart>? previous;
  final double progress;
  final int? spokeHoleCount;
  final Map<HubGuidePart, Rect> hits;

  late double _s;
  late double _dx;
  late double _dy;

  Offset _p(double x, double y) => Offset(_dx + x * _s, _dy + y * _s);
  double _d(double v) => v * _s;

  /// 0 → 1 as [part] becomes highlighted; blends the previous selection out.
  double _lit(HubGuidePart part) {
    final now = current?.contains(part) == true ? 1.0 : 0.0;
    final before = previous?.contains(part) == true ? 1.0 : 0.0;
    return before + (now - before) * progress;
  }

  bool get _anySelected => current != null && current!.isNotEmpty;

  /// How much the non-selected dimensions recede.
  double get _recede {
    final now = _anySelected ? 1.0 : 0.0;
    final before = previous != null && previous!.isNotEmpty ? 1.0 : 0.0;
    return before + (now - before) * progress;
  }

  Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    _s = math.min(size.width / _G.w, size.height / _G.h);
    _dx = (size.width - _G.w * _s) / 2;
    _dy = (size.height - _G.h * _s) / 2;

    _paintCentreLines(canvas);
    _paintSection(canvas);
    _paintEndView(canvas);
    _paintDimensions(canvas);
    _paintCaptions(canvas);
  }

  // ---------------------------------------------------------------- lines --

  /// Line weights follow the scale only in part: at sidebar size a purely
  /// proportional hairline vanishes, at dialog size a fixed one looks thin.
  double _lineWidth(double width) => math.max(1.0, width * (0.55 + 0.45 * _s));

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = _lineWidth(width)
    ..strokeCap = StrokeCap.butt
    ..strokeJoin = StrokeJoin.miter;

  Paint _fillPaint(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  void _dashed(Canvas canvas, Path path, Paint paint, List<double> pattern) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var index = 0;
      while (distance < metric.length) {
        final segment = _d(pattern[index % pattern.length]);
        if (index.isEven) {
          canvas.drawPath(
              metric.extractPath(distance, math.min(distance + segment, metric.length)),
              paint);
        }
        distance += segment;
        index++;
      }
    }
  }

  void _centreLine(Canvas canvas, Offset a, Offset b, Color color) {
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
    _dashed(canvas, path, _stroke(color, 1.2), const [14, 5, 3, 5]);
  }

  void _paintCentreLines(Canvas canvas) {
    final ink = palette.inkMuted.withValues(alpha: 0.7);
    // axle axis
    _centreLine(canvas, _p(_G.axleLeft - 24, _G.axisY),
        _p(_G.axleDimX + 16, _G.axisY), ink);
    // wheel centre line, lit with the centre-to-flange dimensions
    final lit = math.max(_lit(HubGuidePart.centerToLeft),
        _lit(HubGuidePart.centerToRight));
    _centreLine(canvas, _p(_G.centerX, _G.centerY - 26),
        _p(_G.centerX, _G.oldY - 14), _mix(ink, palette.accent, lit));
    // flange centre lines (short, above the flanges)
    for (final x in [_G.flangeLX, _G.flangeRX]) {
      _centreLine(canvas, _p(x, _G.ftfY - 18),
          _p(x, _G.axisY - _G.pcdL / 2 - _G.flangeLip - 6), ink);
    }
    // end view centre lines
    _centreLine(canvas, _p(_G.evCx - _G.evR - 18, _G.evCy),
        _p(_G.evCx + _G.evR + 18, _G.evCy), ink);
    _centreLine(canvas, _p(_G.evCx, _G.evCy - _G.evR - 18),
        _p(_G.evCx, _G.evCy + _G.evR + 18), ink);
  }

  // -------------------------------------------------------------- section --

  void _part(Canvas canvas, Path path, double lit,
      {bool deep = false}) {
    final fill = _mix(deep ? palette.fillDeep : palette.fill,
        palette.accentContainer, lit);
    final edge = _mix(palette.ink.withValues(alpha: 0.85), palette.accent, lit);
    canvas.drawPath(path, _fillPaint(fill));
    canvas.drawPath(path, _stroke(edge, 1.6 + 0.8 * lit));
  }

  Path _rect(double x1, double y1, double x2, double y2, [double radius = 0]) {
    final rect = Rect.fromPoints(_p(x1, y1), _p(x2, y2));
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(_d(radius))));
  }

  void _paintSection(Canvas canvas) {
    final axleLit = _lit(HubGuidePart.axleBody);
    final endsLit = _lit(HubGuidePart.axleEnds);
    final rotorLit = _lit(HubGuidePart.rotorMount);
    final driveLit = _lit(HubGuidePart.driveReceiver);
    final bearingLit = _lit(HubGuidePart.bearings);
    final holesLit = _lit(HubGuidePart.spokeHoles);

    // Axle (hollow): body first so every other part sits on top of it.
    _part(
        canvas,
        _rect(_G.axleLeft, _G.axisY - _G.axleR, _G.axleRight,
            _G.axisY + _G.axleR, 3),
        math.max(axleLit, endsLit),
        deep: true);
    // bore lines
    final bore = _stroke(
        _mix(palette.inkMuted, palette.accent, math.max(axleLit, endsLit)), 1);
    canvas.drawLine(_p(_G.axleLeft, _G.axisY - _G.boreR),
        _p(_G.axleRight, _G.axisY - _G.boreR), bore);
    canvas.drawLine(_p(_G.axleLeft, _G.axisY + _G.boreR),
        _p(_G.axleRight, _G.axisY + _G.boreR), bore);
    // axle ends (where a QR skewer or a thru axle passes)
    if (endsLit > 0) {
      final glow = _fillPaint(palette.accent.withValues(alpha: 0.28 * endsLit));
      canvas.drawRect(
          Rect.fromPoints(_p(_G.axleLeft - 4, _G.axisY - _G.axleR - 6),
              _p(_G.oldLeft, _G.axisY + _G.axleR + 6)),
          glow);
      canvas.drawRect(
          Rect.fromPoints(_p(_G.oldRight, _G.axisY - _G.axleR - 6),
              _p(_G.axleRight + 4, _G.axisY + _G.axleR + 6)),
          glow);
    }

    // Barrel between the flanges.
    _part(
        canvas,
        _rect(_G.flangeLX, _G.axisY - _G.barrelR, _G.flangeRX,
            _G.axisY + _G.barrelR, 10),
        0);

    // Freehub body: splined cylinder from the drive flange to the right cap.
    const fhTop = _G.axisY - _G.freehubR;
    const fhBottom = _G.axisY + _G.freehubR;
    _part(
        canvas,
        _rect(_G.flangeRX + _G.flangeT / 2, fhTop, _G.freehubRight, fhBottom, 6),
        driveLit);
    final spline = _stroke(
        _mix(palette.inkMuted, palette.accent, driveLit).withValues(alpha: 0.9),
        1);
    for (var i = 1; i <= 3; i++) {
      final y = fhTop + (fhBottom - fhTop) * i / 4;
      canvas.drawLine(_p(_G.flangeRX + _G.flangeT / 2 + 8, y),
          _p(_G.freehubRight - 8, y), spline);
    }

    // End caps / locknuts at the OLD faces.
    _part(
        canvas,
        _rect(_G.oldLeft, _G.axisY - _G.capR, _G.oldLeft + _G.capW,
            _G.axisY + _G.capR, 3),
        endsLit,
        deep: true);
    _part(
        canvas,
        _rect(_G.oldRight - _G.capW, _G.axisY - _G.capR, _G.oldRight,
            _G.axisY + _G.capR, 3),
        endsLit,
        deep: true);

    // Rotor mount flange (6 bolts) beside the left cap.
    _part(
        canvas,
        _rect(_G.rotorX - _G.rotorW / 2, _G.axisY - _G.rotorR,
            _G.rotorX + _G.rotorW / 2, _G.axisY + _G.rotorR, 4),
        rotorLit);
    final bolt = _stroke(_mix(palette.ink, palette.accent, rotorLit), 1.2);
    for (final sign in [-1, 1]) {
      canvas.drawCircle(_p(_G.rotorX, _G.axisY + sign * _G.rotorBoltY),
          _d(4), bolt);
    }

    // Spoke flanges with their holes (section shows the top and bottom hole).
    for (final side in [
      (x: _G.flangeLX, pcd: _G.pcdL),
      (x: _G.flangeRX, pcd: _G.pcdR),
    ]) {
      final outer = side.pcd / 2 + _G.flangeLip;
      _part(
          canvas,
          _rect(side.x - _G.flangeT / 2, _G.axisY - outer,
              side.x + _G.flangeT / 2, _G.axisY + outer, 5),
          0);
      final holeEdge = _stroke(_mix(palette.ink, palette.accent, holesLit),
          1.4 + holesLit);
      final holeFill = _fillPaint(_mix(palette.paper,
          palette.accentContainer, holesLit));
      for (final sign in [-1, 1]) {
        final c = _p(side.x, _G.axisY + sign * side.pcd / 2);
        canvas.drawCircle(c, _d(_G.holeR), holeFill);
        canvas.drawCircle(c, _d(_G.holeR), holeEdge);
      }
    }

    // Bearings: cartridge sections above and below the axle.
    final bearingEdge = _stroke(
        _mix(palette.ink.withValues(alpha: 0.85), palette.accent, bearingLit),
        1.4);
    final bearingFill =
        _fillPaint(_mix(palette.paper, palette.accentContainer, bearingLit));
    // Shell bearings sit just inside each flange; the freehub carries its own.
    for (final x in [_G.flangeLX + 24, _G.flangeRX - 24, _G.freehubRight - 22]) {
      final r = x > _G.flangeRX ? _G.freehubR : _G.barrelR;
      for (final sign in [-1, 1]) {
        final rect = Rect.fromCenter(
            center: _p(x, _G.axisY + sign * (_G.axleR + (r - _G.axleR) / 2)),
            width: _d(20),
            height: _d(r - _G.axleR - 8));
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(_d(2)));
        canvas.drawRRect(rr, bearingFill);
        canvas.drawRRect(rr, bearingEdge);
        canvas.drawCircle(rect.center, _d(4), bearingEdge);
      }
    }
  }

  // ------------------------------------------------------------- end view --

  void _paintEndView(Canvas canvas) {
    final holesLit = _lit(HubGuidePart.spokeHoles);
    final holeDiaLit = _lit(HubGuidePart.spokeHoleDiameter);
    final pcdLit = math.max(_lit(HubGuidePart.pcdLeft), _lit(HubGuidePart.pcdRight));
    final rotorLit = _lit(HubGuidePart.rotorMount);
    final axleLit = math.max(_lit(HubGuidePart.axleDiameter), _lit(HubGuidePart.axleBody));
    final c = _p(_G.evCx, _G.evCy);

    // flange disc
    canvas.drawCircle(c, _d(_G.evR), _fillPaint(palette.fill));
    canvas.drawCircle(c, _d(_G.evR), _stroke(palette.ink.withValues(alpha: 0.85), 1.6));
    // pitch circle
    final pcdPath = Path()..addOval(Rect.fromCircle(center: c, radius: _d(_G.evPcd)));
    _dashed(canvas, pcdPath,
        _stroke(_mix(palette.inkMuted, palette.accent, pcdLit), 1.1 + pcdLit),
        const [10, 4, 2, 4]);
    // spoke holes
    final count = (spokeHoleCount ?? 0) >= 12 && (spokeHoleCount ?? 0) <= 48
        ? spokeHoleCount!
        : 16;
    final holeEdge = _stroke(_mix(palette.ink, palette.accent, holesLit), 1.3 + holesLit);
    final holeFill = _fillPaint(_mix(palette.paper, palette.accentContainer, holesLit));
    final holeRadius = count > 32 ? 5.0 : 6.5;
    for (var i = 0; i < count; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / count;
      final h = Offset(c.dx + _d(_G.evPcd) * math.cos(a),
          c.dy + _d(_G.evPcd) * math.sin(a));
      canvas.drawCircle(h, _d(holeRadius), holeFill);
      canvas.drawCircle(h, _d(holeRadius), holeEdge);
    }
    // rotor bolts (6)
    final boltEdge = _stroke(_mix(palette.ink, palette.accent, rotorLit), 1.2 + rotorLit);
    final boltFill = _fillPaint(_mix(palette.paper, palette.accentContainer, rotorLit));
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / 6;
      final b = Offset(c.dx + _d(_G.evBoltR) * math.cos(a),
          c.dy + _d(_G.evBoltR) * math.sin(a));
      canvas.drawCircle(b, _d(4.5), boltFill);
      canvas.drawCircle(b, _d(4.5), boltEdge);
    }
    // axle bore in the middle
    canvas.drawCircle(c, _d(_G.axleR),
        _fillPaint(_mix(palette.fillDeep, palette.accentContainer, axleLit)));
    canvas.drawCircle(c, _d(_G.axleR),
        _stroke(_mix(palette.ink, palette.accent, axleLit), 1.4));
    canvas.drawCircle(c, _d(_G.boreR), _stroke(palette.inkMuted, 1));

    // PCD as a diameter through two opposite holes (only when the count is even
    // the holes are opposite; the arrows still end on the pitch circle).
    const angle = -math.pi / 4;
    final a1 = Offset(c.dx + _d(_G.evPcd) * math.cos(angle),
        c.dy + _d(_G.evPcd) * math.sin(angle));
    final a2 = Offset(c.dx - _d(_G.evPcd) * math.cos(angle),
        c.dy - _d(_G.evPcd) * math.sin(angle));
    _dimensionLine(canvas, a2, a1, 'PCD',
        lit: pcdLit, part: HubGuidePart.pcdLeft, labelAt: 0.76);

    // spoke hole diameter: leader from the top-right hole to a label
    final holeAngle = -math.pi / 2 + 2 * math.pi * (count >= 16 ? 2 : 1) / count;
    final hole = Offset(c.dx + _d(_G.evPcd) * math.cos(holeAngle),
        c.dy + _d(_G.evPcd) * math.sin(holeAngle));
    final leaderEnd = _p(_G.evCx + _G.evR + 6, _G.evCy - _G.evR + 4);
    _leader(canvas, hole, leaderEnd, 'Ø hoyo',
        lit: holeDiaLit, part: HubGuidePart.spokeHoleDiameter);
    if (holeDiaLit > 0) {
      canvas.drawCircle(hole, _d(holeRadius + 6),
          _stroke(palette.accent.withValues(alpha: holeDiaLit), 1.6));
    }
  }

  // ----------------------------------------------------------- dimensions --

  void _paintDimensions(Canvas canvas) {
    const topL = _G.axisY - _G.pcdL / 2;
    const bottomL = _G.axisY + _G.pcdL / 2;
    const topR = _G.axisY - _G.pcdR / 2;
    const bottomR = _G.axisY + _G.pcdR / 2;

    // OLD: locknut face to locknut face.
    _extension(canvas, _p(_G.oldLeft, _G.axisY + _G.capR), _p(_G.oldLeft, _G.oldY),
        lit: _lit(HubGuidePart.old));
    _extension(canvas, _p(_G.oldRight, _G.axisY + _G.capR), _p(_G.oldRight, _G.oldY),
        lit: _lit(HubGuidePart.old));
    _dimensionLine(canvas, _p(_G.oldLeft, _G.oldY), _p(_G.oldRight, _G.oldY), 'OLD',
        lit: _lit(HubGuidePart.old), part: HubGuidePart.old);

    // Flange to flange, centre to centre.
    _dimensionLine(canvas, _p(_G.flangeLX, _G.ftfY), _p(_G.flangeRX, _G.ftfY),
        'entre bridas',
        lit: _lit(HubGuidePart.flangeToFlange), part: HubGuidePart.flangeToFlange);

    // Centre to each flange.
    _dimensionLine(canvas, _p(_G.flangeLX, _G.centerY), _p(_G.centerX, _G.centerY),
        'centro→izq',
        lit: _lit(HubGuidePart.centerToLeft), part: HubGuidePart.centerToLeft);
    _dimensionLine(canvas, _p(_G.centerX, _G.centerY), _p(_G.flangeRX, _G.centerY),
        'centro→der',
        lit: _lit(HubGuidePart.centerToRight), part: HubGuidePart.centerToRight);

    // PCD left, drawn outside the left end, from hole centre to hole centre.
    final pcdLLit = _lit(HubGuidePart.pcdLeft);
    _extension(canvas, _p(_G.flangeLX - _G.flangeT / 2 - 2, topL), _p(_G.pcdLeftX - 8, topL),
        lit: pcdLLit);
    _extension(canvas, _p(_G.flangeLX - _G.flangeT / 2 - 2, bottomL),
        _p(_G.pcdLeftX - 8, bottomL),
        lit: pcdLLit);
    _dimensionLine(canvas, _p(_G.pcdLeftX, topL), _p(_G.pcdLeftX, bottomL), 'PCD izq',
        lit: pcdLLit, part: HubGuidePart.pcdLeft, labelAt: 0.3);

    // PCD right, outside the right end.
    final pcdRLit = _lit(HubGuidePart.pcdRight);
    _extension(canvas, _p(_G.flangeRX + _G.flangeT / 2 + 2, topR), _p(_G.pcdRightX + 8, topR),
        lit: pcdRLit);
    _extension(canvas, _p(_G.flangeRX + _G.flangeT / 2 + 2, bottomR),
        _p(_G.pcdRightX + 8, bottomR),
        lit: pcdRLit);
    _dimensionLine(canvas, _p(_G.pcdRightX, topR), _p(_G.pcdRightX, bottomR), 'PCD der',
        lit: pcdRLit, part: HubGuidePart.pcdRight, labelAt: 0.3);

    // Axle diameter at the protruding end.
    final axleLit = _lit(HubGuidePart.axleDiameter);
    _extension(canvas, _p(_G.axleRight + 2, _G.axisY - _G.axleR),
        _p(_G.axleDimX + 8, _G.axisY - _G.axleR),
        lit: axleLit);
    _extension(canvas, _p(_G.axleRight + 2, _G.axisY + _G.axleR),
        _p(_G.axleDimX + 8, _G.axisY + _G.axleR),
        lit: axleLit);
    _dimensionLine(canvas, _p(_G.axleDimX, _G.axisY - _G.axleR),
        _p(_G.axleDimX, _G.axisY + _G.axleR), 'Ø eje',
        lit: axleLit, part: HubGuidePart.axleDiameter, labelAt: 1.9);
  }

  Color _dimColor(double lit) {
    final base = _mix(palette.inkMuted,
        palette.inkMuted.withValues(alpha: 0.32), _recede);
    return _mix(base, palette.accent, lit);
  }

  void _extension(Canvas canvas, Offset from, Offset to, {required double lit}) {
    canvas.drawLine(from, to, _stroke(_dimColor(lit), 0.9));
  }

  void _arrow(Canvas canvas, Offset tip, Offset from, Paint paint) {
    final v = (tip - from);
    final len = v.distance;
    if (len == 0) return;
    final u = v / len;
    final n = Offset(-u.dy, u.dx);
    final l = _d(11);
    final w = _d(3.4);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - u.dx * l + n.dx * w, tip.dy - u.dy * l + n.dy * w)
      ..lineTo(tip.dx - u.dx * l - n.dx * w, tip.dy - u.dy * l - n.dy * w)
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  /// A linear dimension: line with an arrowhead at each end and its label on
  /// the line, on a small pill of paper so it reads over the drawing.
  void _dimensionLine(Canvas canvas, Offset a, Offset b, String text,
      {required double lit, required HubGuidePart part, double labelAt = 0.5}) {
    final color = _dimColor(lit);
    final line = _stroke(color, 1.1 + 1.1 * lit);
    canvas.drawLine(a, b, line);
    _arrow(canvas, a, b, Paint()..color = color);
    _arrow(canvas, b, a, Paint()..color = color);
    final mid = Offset(a.dx + (b.dx - a.dx) * labelAt, a.dy + (b.dy - a.dy) * labelAt);
    _label(canvas, mid, text, lit: lit, part: part);
  }

  void _leader(Canvas canvas, Offset from, Offset to, String text,
      {required double lit, required HubGuidePart part}) {
    final color = _dimColor(lit);
    canvas.drawLine(from, to, _stroke(color, 1 + lit));
    canvas.drawCircle(from, _d(2.2), Paint()..color = color);
    _label(canvas, to + Offset(_d(4), 0), text,
        lit: lit, part: part, anchor: Alignment.centerLeft);
  }

  /// Below dialog size only the lit dimension carries its name: at sidebar
  /// width twenty labels collide and hide the drawing they describe.
  bool get _labelsForAll => _s >= 0.5;

  void _label(Canvas canvas, Offset at, String text,
      {required double lit,
      required HubGuidePart part,
      Alignment anchor = Alignment.center}) {
    final fontSize = _s < 0.4 ? 10.5 : (_s < 0.7 ? 12.0 : 13.5);
    if (!_labelsForAll && lit < 0.05) {
      // keep the hit target so a tap still opens the field
      final probe = TextPainter(
          text: TextSpan(text: text, style: labelStyle.copyWith(fontSize: fontSize)),
          textDirection: TextDirection.ltr)
        ..layout();
      final rect = Rect.fromCenter(
          center: at, width: probe.width + 10, height: probe.height + 4);
      hits[part] = hits.containsKey(part) ? hits[part]!.expandToInclude(rect) : rect;
      return;
    }
    final color = _mix(_dimColor(lit), palette.onAccentContainer, lit);
    final painter = TextPainter(
      text: TextSpan(
          text: text,
          style: labelStyle.copyWith(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.1,
              fontFeatures: const [ui.FontFeature.tabularFigures()])),
      textDirection: TextDirection.ltr,
    )..layout();
    const padX = 5.0, padY = 2.0;
    final w = painter.width + padX * 2;
    final h = painter.height + padY * 2;
    final left = at.dx - w / 2 - anchor.x * (-w / 2);
    final top = at.dy - h / 2 - anchor.y * (-h / 2);
    final rect = Rect.fromLTWH(left, top, w, h);
    final pill = RRect.fromRectAndRadius(rect, Radius.circular(h / 2));
    canvas.drawRRect(
        pill,
        _fillPaint(_mix(palette.paper, palette.accentContainer, lit)));
    if (lit > 0) {
      canvas.drawRRect(pill, _stroke(palette.accent.withValues(alpha: lit), 1));
    }
    painter.paint(canvas, Offset(rect.left + padX, rect.top + padY));
    hits[part] = hits.containsKey(part) ? hits[part]!.expandToInclude(rect) : rect;
  }

  void _paintCaptions(Canvas canvas) {
    final style = labelStyle.copyWith(
        fontSize: _s < 0.4 ? 9.5 : 11,
        color: palette.inkMuted,
        fontStyle: FontStyle.italic);
    for (final caption in [
      ('Corte por el eje', _p(_G.centerX, _G.h - 34)),
      ('Brida de frente', _p(_G.evCx, _G.h - 34)),
    ]) {
      final painter = TextPainter(
          text: TextSpan(text: caption.$1, style: style),
          textDirection: TextDirection.ltr)
        ..layout();
      painter.paint(canvas,
          caption.$2 - Offset(painter.width / 2, painter.height / 2));
    }
  }

  @override
  bool shouldRepaint(_HubGuidePainter old) =>
      old.current != current ||
      old.previous != previous ||
      old.progress != progress ||
      old.spokeHoleCount != spokeHoleCount ||
      old.palette != palette ||
      old.labelStyle != labelStyle;
}

/// The guide as the form shows it: the drawing, the name and explanation of
/// the field the operator is on, and the list of measures to jump to.
class HubMeasureGuidePanel extends StatelessWidget {
  const HubMeasureGuidePanel({
    super.key,
    required this.highlightedKey,
    required this.labelFor,
    required this.helperFor,
    required this.availableKeys,
    required this.onSelect,
    this.spokeHoleCount,
    this.onExpand,
    this.showChips = true,
  });

  /// Spec field the operator is on, or null.
  final String? highlightedKey;
  final String Function(String key) labelFor;
  final String? Function(String key) helperFor;

  /// Fields the sheet currently shows (the guide only lists those).
  final List<String> availableKeys;
  final ValueChanged<String> onSelect;
  final int? spokeHoleCount;
  final VoidCallback? onExpand;

  /// The list of measures to jump to; the sidebar leaves it to the dialog.
  final bool showChips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final key = highlightedKey;
    final hasPlace = key != null && hubGuidePartsForField(key) != null;
    final listed = hubGuideFieldKeys.where(availableKeys.contains).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 2),
            child: HubMeasureGuide(
              highlightedKey: key,
              spokeHoleCount: spokeHoleCount,
              onFieldTap: onSelect,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // No AnimatedSwitcher here: hovering back to the same field before the
        // fade ended put two entries with one key in its Stack (2026-09-17).
        // The drawing already animates its own highlight.
        Text(
          key == null
              ? 'Toca un campo de la ficha y el dibujo te muestra dónde se mide.'
              : labelFor(key),
          key: const ValueKey('hub-guide-title'),
          style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: key == null ? scheme.onSurfaceVariant : scheme.onSurface),
        ),
        if (key != null && (helperFor(key)?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 4),
          Text(helperFor(key)!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
        ],
        if (key != null && !hasPlace) ...[
          const SizedBox(height: 4),
          Text('Este dato no es una medida del dibujo.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        if (showChips && listed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in listed)
                ChoiceChip(
                  key: ValueKey('hub-guide-chip-$k'),
                  label: Text(labelFor(k)),
                  selected: k == key,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onSelect(k),
                ),
            ],
          ),
        ],
        if (onExpand != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('hub-guide-expand'),
              onPressed: onExpand,
              icon: const Icon(Icons.open_in_full, size: 16),
              label: const Text('Ver más grande'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Large version of the guide in a dialog, with its own selection so the
/// operator can walk every measure without leaving the form.
Future<void> showHubMeasureGuideDialog(
  BuildContext context, {
  required String? initialKey,
  required String Function(String key) labelFor,
  required String? Function(String key) helperFor,
  required List<String> availableKeys,
  int? spokeHoleCount,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      var selected = initialKey;
      return StatefulBuilder(
        builder: (context, setState) {
          final width = math.min(980.0, MediaQuery.sizeOf(context).width - 48);
          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Dónde se mide cada dato de la maza',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      HubMeasureGuidePanel(
                        highlightedKey: selected,
                        labelFor: labelFor,
                        helperFor: helperFor,
                        availableKeys: availableKeys,
                        spokeHoleCount: spokeHoleCount,
                        onSelect: (key) => setState(() => selected = key),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
