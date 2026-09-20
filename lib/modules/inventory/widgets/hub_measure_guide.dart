import 'dart:math' as math;

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

enum HubGuidePosition { front, rear, universal, pair, unknown }

enum HubGuideRotorInterface { none, sixBolt, centerLock, generic, unknown }

enum HubGuideDriveInterface {
  none,
  cassette,
  threadedFreewheel,
  fixedThread,
  lockringCog,
  bmxDriver,
  generic,
  unknown,
}

enum HubGuideBearingSystem { sealed, loose, mixed, unknown }

enum HubGuideAxleMount {
  quickRelease,
  thruAxle,
  nutted,
  femaleBolt,
  generic,
  unknown,
}

/// The parts the drawing may show for the currently declared hub.
///
/// This projection is deliberately fail-closed: an attachment is omitted when
/// its prerequisite is missing or physically contradicts the package
/// position. Stale values therefore cannot turn a front hub into a cassette
/// hub in the guide.
class HubGuideConfiguration {
  const HubGuideConfiguration({
    this.position = HubGuidePosition.unknown,
    this.rotorInterface = HubGuideRotorInterface.unknown,
    this.driveInterface = HubGuideDriveInterface.unknown,
    this.bearingSystem = HubGuideBearingSystem.unknown,
    this.axleMount = HubGuideAxleMount.unknown,
  });

  factory HubGuideConfiguration.fromSpecValues(Map<String, dynamic> values) {
    final position = switch (values['hub_package_position']) {
      'Delantera' => HubGuidePosition.front,
      'Trasera' => HubGuidePosition.rear,
      'Universal' => HubGuidePosition.universal,
      'Juego (delantera y trasera)' ||
      'Juego delantera + trasera' =>
        HubGuidePosition.pair,
      _ => HubGuidePosition.unknown,
    };

    final rotorPresent = values['hub_rotor_mount_present'];
    final rotorInterface = position == HubGuidePosition.pair
        ? HubGuideRotorInterface.unknown
        : switch (rotorPresent) {
            false => HubGuideRotorInterface.none,
            true => switch (values['rotor_mount_type']) {
                '6 pernos' => HubGuideRotorInterface.sixBolt,
                'Centerlock' ||
                'Center Lock' =>
                  HubGuideRotorInterface.centerLock,
                'Desconocido / sin confirmar' ||
                null =>
                  HubGuideRotorInterface.generic,
                _ => HubGuideRotorInterface.generic,
              },
            _ => HubGuideRotorInterface.unknown,
          };

    final drivePresent = values['hub_drive_receiver_present'];
    final HubGuideDriveInterface driveInterface;
    if (position == HubGuidePosition.front) {
      driveInterface = HubGuideDriveInterface.none;
    } else if (position != HubGuidePosition.rear) {
      driveInterface = drivePresent == false
          ? HubGuideDriveInterface.none
          : HubGuideDriveInterface.unknown;
    } else if (drivePresent == false) {
      driveInterface = HubGuideDriveInterface.none;
    } else if (drivePresent != true) {
      driveInterface = HubGuideDriveInterface.unknown;
    } else {
      driveInterface = switch (values['hub_drive_receiver_kind']) {
        'Núcleo de cassette' ||
        'Núcleo estriado de cassette' =>
          HubGuideDriveInterface.cassette,
        'Rosca para piñón (rueda libre)' ||
        'Rosca para rueda libre' =>
          HubGuideDriveInterface.threadedFreewheel,
        'Rosca para piñón fijo' ||
        'Rosca para piñón fijo y contratuerca' =>
          HubGuideDriveInterface.fixedThread,
        'Piñón retenido por anillo' => HubGuideDriveInterface.lockringCog,
        'Driver BMX' => HubGuideDriveInterface.bmxDriver,
        'Otro' || 'Otra interfaz OEM' => HubGuideDriveInterface.generic,
        _ => HubGuideDriveInterface.unknown,
      };
    }

    final bearingSystem = position == HubGuidePosition.pair
        ? HubGuideBearingSystem.unknown
        : switch (values['bearing_system']) {
            'Sellados' ||
            'Rodamientos sellados' =>
              HubGuideBearingSystem.sealed,
            'Bolas sueltas' => HubGuideBearingSystem.loose,
            'Mixto' => HubGuideBearingSystem.mixed,
            _ => HubGuideBearingSystem.unknown,
          };

    final axleMount = position == HubGuidePosition.pair
        ? HubGuideAxleMount.unknown
        : switch (values['hub_axle_mount_kind']) {
            'Cierre rápido' => HubGuideAxleMount.quickRelease,
            'Eje pasante' => HubGuideAxleMount.thruAxle,
            'Eje con tuercas' => HubGuideAxleMount.nutted,
            'Eje hembra con pernos' => HubGuideAxleMount.femaleBolt,
            'Otra interfaz OEM' => HubGuideAxleMount.generic,
            _ => HubGuideAxleMount.unknown,
          };

    return HubGuideConfiguration(
      position: position,
      rotorInterface: rotorInterface,
      driveInterface: driveInterface,
      bearingSystem: bearingSystem,
      axleMount: axleMount,
    );
  }

  final HubGuidePosition position;
  final HubGuideRotorInterface rotorInterface;
  final HubGuideDriveInterface driveInterface;
  final HubGuideBearingSystem bearingSystem;
  final HubGuideAxleMount axleMount;

  bool get isPackageSet => position == HubGuidePosition.pair;

  String get semanticLabel {
    final positionText = switch (position) {
      HubGuidePosition.front => 'maza delantera',
      HubGuidePosition.rear => 'maza trasera',
      HubGuidePosition.universal => 'maza de posición universal',
      HubGuidePosition.pair => 'juego de mazas delantera y trasera',
      HubGuidePosition.unknown => 'maza de posición sin confirmar',
    };
    final rotorText = switch (rotorInterface) {
      HubGuideRotorInterface.none => 'sin anclaje de disco',
      HubGuideRotorInterface.sixBolt => 'con anclaje de disco de 6 pernos',
      HubGuideRotorInterface.centerLock => 'con anclaje de disco Centerlock',
      HubGuideRotorInterface.generic =>
        'con anclaje de disco de tipo sin confirmar',
      HubGuideRotorInterface.unknown => 'anclaje de disco sin confirmar',
    };
    final driveText = switch (driveInterface) {
      HubGuideDriveInterface.none => 'sin montaje para piñón',
      HubGuideDriveInterface.cassette => 'con núcleo de cassette',
      HubGuideDriveInterface.threadedFreewheel => 'con rosca para rueda libre',
      HubGuideDriveInterface.fixedThread => 'con rosca para piñón fijo',
      HubGuideDriveInterface.lockringCog => 'con piñón retenido por anillo',
      HubGuideDriveInterface.bmxDriver => 'con núcleo BMX (driver)',
      HubGuideDriveInterface.generic =>
        'con montaje para piñón de tipo sin confirmar',
      HubGuideDriveInterface.unknown => 'montaje del piñón sin confirmar',
    };
    final bearingText = switch (bearingSystem) {
      HubGuideBearingSystem.sealed => 'rodamientos sellados',
      HubGuideBearingSystem.loose => 'rodamientos de bolas sueltas',
      HubGuideBearingSystem.mixed => 'sistema de rodamientos mixto',
      HubGuideBearingSystem.unknown => 'rodamientos sin confirmar',
    };
    final axleText = switch (axleMount) {
      HubGuideAxleMount.quickRelease => 'cierre rápido',
      HubGuideAxleMount.thruAxle => 'eje pasante',
      HubGuideAxleMount.nutted => 'eje con tuercas',
      HubGuideAxleMount.femaleBolt => 'eje hembra con pernos',
      HubGuideAxleMount.generic => 'sujeción OEM',
      HubGuideAxleMount.unknown => 'sujeción de eje sin confirmar',
    };
    return 'Dibujo de $positionText, $rotorText, $driveText, '
        '$bearingText y $axleText.';
  }

  @override
  bool operator ==(Object other) =>
      other is HubGuideConfiguration &&
      position == other.position &&
      rotorInterface == other.rotorInterface &&
      driveInterface == other.driveInterface &&
      bearingSystem == other.bearingSystem &&
      axleMount == other.axleMount;

  @override
  int get hashCode => Object.hash(
      position, rotorInterface, driveInterface, bearingSystem, axleMount);
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
      'hub_axle_diameter_mm' => const {HubGuidePart.axleDiameter},
      'hub_axle_diameter_datum' => const {
          HubGuidePart.axleDiameter,
          HubGuidePart.axleBody
        },
      'hub_axle_mount_kind' => const {HubGuidePart.axleEnds},
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
  'hub_axle_diameter_datum',
  'hub_axle_diameter_mm',
  'hub_axle_mount_kind',
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

/// Technical drawing of the declared hub: a section through the axle, with
/// the wheel centre line, and the left flange seen from the front. Optional
/// hardware is shown only when [configuration] confirms it.
///
/// [highlightedKey] is the spec field the operator is on: its parts are drawn
/// in the accent role and every other dimension recedes. Tapping a dimension
/// reports its field through [onFieldTap].
class HubMeasureGuide extends StatefulWidget {
  const HubMeasureGuide({
    super.key,
    this.highlightedKey,
    this.spokeHoleCount,
    this.configuration = const HubGuideConfiguration(),
    this.onFieldTap,
    this.aspectRatio = 1000 / 600,
  });

  final String? highlightedKey;
  final int? spokeHoleCount;
  final HubGuideConfiguration configuration;
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

  @override
  void didUpdateWidget(HubMeasureGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedKey != widget.highlightedKey) {
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
    // Several visible parts cross the axle. Prefer the smallest hit region so
    // tapping a rotor, bearing or piñón mount opens that part instead of the
    // long axle rectangle painted behind it.
    final matches = _hits.entries
        .where((entry) =>
            entry.value.inflate(6).contains(details.localPosition))
        .toList()
      ..sort((a, b) =>
          (a.value.width * a.value.height)
              .compareTo(b.value.width * b.value.height));
    for (final entry in matches) {
      final key = hubGuideFieldForPart(entry.key);
      if (key != null) {
        onFieldTap(key);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
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
      label: widget.configuration.semanticLabel,
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
                  progress: reduceMotion ? 1 : _fade.value,
                  spokeHoleCount: widget.spokeHoleCount,
                  configuration: widget.configuration,
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

/// Normalized drawing coordinates. UI colour and type come from the canonical
/// theme; these coordinates describe only the mechanical illustration.
class _G {
  static const w = 1000.0;
  static const h = 600.0;
  static const cy = 310.0;
  static const centreX = 480.0;
  static const axleLeft = 105.0;
  static const axleRight = 895.0;
  static const oldLeft = 165.0;
  static const oldRight = 835.0;
  static const flangeLeft = 310.0;
  static const flangeRight = 650.0;
  static const flangeLeftRadius = 146.0;
  static const flangeRightRadius = 126.0;
  static const shellLeft = 330.0;
  static const shellRight = 630.0;
}

enum _HubGuideScene { side, flange }

class _HubGuidePainter extends CustomPainter {
  _HubGuidePainter({
    required this.palette,
    required this.labelStyle,
    required this.current,
    required this.progress,
    required this.spokeHoleCount,
    required this.configuration,
    required this.hits,
  });

  final _GuidePalette palette;
  final TextStyle labelStyle;
  final Set<HubGuidePart>? current;
  final double progress;
  final int? spokeHoleCount;
  final HubGuideConfiguration configuration;
  final Map<HubGuidePart, Rect> hits;

  late double _scale;
  late double _dx;
  late double _dy;

  Offset _p(double x, double y) => Offset(_dx + x * _scale, _dy + y * _scale);
  double _d(double value) => value * _scale;
  bool get _compact => _scale < 0.5;
  bool _selected(HubGuidePart part) => current?.contains(part) == true;
  double _focus(HubGuidePart part) => _selected(part) ? progress : 0;

  bool get _usesTopDimension =>
      _selected(HubGuidePart.flangeToFlange) ||
      _selected(HubGuidePart.centerToLeft) ||
      _selected(HubGuidePart.centerToRight);

  _HubGuideScene get _scene {
    if (_selected(HubGuidePart.pcdLeft) ||
        _selected(HubGuidePart.pcdRight) ||
        _selected(HubGuidePart.spokeHoleDiameter)) {
      return _HubGuideScene.flange;
    }
    return _HubGuideScene.side;
  }

  Color _mix(Color a, Color b, double amount) =>
      Color.lerp(a, b, amount.clamp(0, 1))!;

  Paint _stroke(Color color, [double width = 1.4]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, width * (0.58 + 0.42 * _scale))
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint _fill(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  void _register(HubGuidePart part, Rect rect) {
    final expanded = rect.inflate(_d(10));
    hits[part] = hits.containsKey(part)
        ? hits[part]!.expandToInclude(expanded)
        : expanded;
  }

  void _dashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final distance = (end - start).distance;
    if (distance == 0) return;
    final direction = (end - start) / distance;
    var cursor = 0.0;
    while (cursor < distance) {
      final dashEnd = math.min(cursor + _d(10), distance);
      canvas.drawLine(
          start + direction * cursor, start + direction * dashEnd, paint);
      cursor += _d(17);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    _scale = math.min(size.width / _G.w, size.height / _G.h);
    _dx = (size.width - _G.w * _scale) / 2;
    _dy = (size.height - _G.h * _scale) / 2;

    switch (_scene) {
      case _HubGuideScene.side:
        _paintSideScene(canvas);
      case _HubGuideScene.flange:
        _paintFlangeScene(canvas);
    }
  }

  void _paintSideScene(Canvas canvas) {
    _orientation(canvas);
    _dashedLine(
      canvas,
      _p(80, _G.cy),
      _p(920, _G.cy),
      _stroke(palette.inkMuted.withValues(alpha: 0.46), 1),
    );

    _paintAxle(canvas);
    _paintHubShell(canvas);
    _paintRotorInterface(canvas);
    _paintDriveInterface(canvas);
    _paintBearings(canvas);
    _paintSideMeasurement(canvas);

    _caption(canvas, _p(500, 567), 'VISTA LATERAL');
  }

  void _orientation(Canvas canvas) {
    // At sidebar width the active upper dimension occupies the same vertical
    // band as the orientation captions. Its own label names the side, so keep
    // that measurement readable instead of stacking three labels together.
    if (!_compact || !_usesTopDimension) {
      _caption(canvas, _p(128, 52), 'LADO IZQUIERDO',
          align: Alignment.centerLeft);
      _caption(canvas, _p(872, 52), 'LADO DERECHO',
          align: Alignment.centerRight);
      _caption(canvas, _p(_G.centreX, 72), 'CENTRO');
    }
    _dashedLine(
      canvas,
      _p(_G.centreX, 82),
      _p(_G.centreX, 488),
      _stroke(palette.inkMuted.withValues(alpha: 0.52), 1),
    );
  }

  void _paintAxle(Canvas canvas) {
    final bodyFocus = math.max(
      _focus(HubGuidePart.axleBody),
      _focus(HubGuidePart.axleDiameter),
    );
    final endFocus = _focus(HubGuidePart.axleEnds);
    final axleColor =
        _mix(palette.fillDeep, palette.accentContainer, bodyFocus);
    final axleEdge = _mix(palette.ink, palette.accent, bodyFocus);
    final axleRadius =
        configuration.axleMount == HubGuideAxleMount.thruAxle ? 17.0 : 12.0;
    final axleRect = Rect.fromPoints(
      _p(_G.axleLeft, _G.cy - axleRadius),
      _p(_G.axleRight, _G.cy + axleRadius),
    );
    final axle = RRect.fromRectAndRadius(axleRect, Radius.circular(_d(6)));
    canvas.drawRRect(axle, _fill(axleColor));
    canvas.drawRRect(axle, _stroke(axleEdge, 1.6));
    _register(HubGuidePart.axleBody, axleRect);
    _register(HubGuidePart.axleDiameter, axleRect);

    if (configuration.axleMount == HubGuideAxleMount.thruAxle ||
        configuration.axleMount == HubGuideAxleMount.quickRelease) {
      final bore = _stroke(
        _mix(palette.inkMuted, palette.accent, bodyFocus),
        1.1,
      );
      canvas.drawLine(
          _p(_G.axleLeft, _G.cy - 4), _p(_G.axleRight, _G.cy - 4), bore);
      canvas.drawLine(
          _p(_G.axleLeft, _G.cy + 4), _p(_G.axleRight, _G.cy + 4), bore);
    }

    final leftEnd = Rect.fromPoints(
      _p(_G.axleLeft - 8, _G.cy - 28),
      _p(_G.oldLeft + 24, _G.cy + 28),
    );
    final rightEnd = Rect.fromPoints(
      _p(_G.oldRight - 24, _G.cy - 28),
      _p(_G.axleRight + 8, _G.cy + 28),
    );
    _paintAxleEnds(canvas, leftEnd, rightEnd, endFocus);
    _register(HubGuidePart.axleEnds, leftEnd);
    _register(HubGuidePart.axleEnds, rightEnd);
  }

  void _paintAxleEnds(
      Canvas canvas, Rect leftEnd, Rect rightEnd, double focus) {
    final edge = _mix(palette.ink, palette.accent, focus);
    final fill = _mix(palette.fillDeep, palette.accentContainer, focus);
    switch (configuration.axleMount) {
      case HubGuideAxleMount.quickRelease:
        final skewer = _stroke(edge, 1.3);
        canvas.drawLine(_p(82, _G.cy), _p(918, _G.cy), skewer);
        final lever = Path()
          ..moveTo(_p(90, _G.cy).dx, _p(90, _G.cy).dy)
          ..quadraticBezierTo(
              _p(56, 275).dx, _p(42, 236).dy, _p(64, 207).dx, _p(64, 207).dy);
        canvas.drawPath(lever, _stroke(edge, 4));
        canvas.drawCircle(_p(88, _G.cy), _d(8), _fill(fill));
        canvas.drawCircle(_p(88, _G.cy), _d(8), _stroke(edge, 1.4));
        _hex(canvas, _p(910, _G.cy), 18, fill, edge);
      case HubGuideAxleMount.nutted:
        _threadMarks(canvas, 105, 154, _G.cy - 12, _G.cy + 12, edge);
        _threadMarks(canvas, 846, 895, _G.cy - 12, _G.cy + 12, edge);
        _hex(canvas, _p(_G.oldLeft, _G.cy), 27, fill, edge);
        _hex(canvas, _p(_G.oldRight, _G.cy), 27, fill, edge);
      case HubGuideAxleMount.femaleBolt:
        for (final x in [_G.oldLeft, _G.oldRight]) {
          canvas.drawCircle(_p(x, _G.cy), _d(25), _fill(fill));
          canvas.drawCircle(_p(x, _G.cy), _d(25), _stroke(edge, 1.5));
          canvas.drawLine(
              _p(x - 9, _G.cy), _p(x + 9, _G.cy), _stroke(edge, 2.2));
        }
      case HubGuideAxleMount.thruAxle:
        for (final x in [_G.oldLeft, _G.oldRight]) {
          canvas.drawCircle(_p(x, _G.cy), _d(23), _fill(fill));
          canvas.drawCircle(_p(x, _G.cy), _d(23), _stroke(edge, 1.5));
          canvas.drawCircle(_p(x, _G.cy), _d(9), _stroke(edge, 1.3));
        }
      case HubGuideAxleMount.generic:
      case HubGuideAxleMount.unknown:
        for (final x in [_G.oldLeft, _G.oldRight]) {
          final rect = Rect.fromCenter(
              center: _p(x, _G.cy), width: _d(38), height: _d(54));
          final shape = RRect.fromRectAndRadius(rect, Radius.circular(_d(7)));
          canvas.drawRRect(shape, _fill(fill));
          canvas.drawRRect(shape, _stroke(edge, 1.5));
        }
    }
  }

  void _hex(
      Canvas canvas, Offset center, double radius, Color fill, Color edge) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 6 + i * math.pi / 3;
      final point = center +
          Offset(_d(radius) * math.cos(angle), _d(radius) * math.sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, _fill(fill));
    canvas.drawPath(path, _stroke(edge, 1.5));
  }

  void _paintHubShell(Canvas canvas) {
    final body = Path()
      ..moveTo(_p(_G.shellLeft, 232).dx, _p(_G.shellLeft, 232).dy)
      ..cubicTo(_p(365, 238).dx, _p(365, 238).dy, _p(380, 258).dx,
          _p(380, 258).dy, _p(410, 265).dx, _p(410, 265).dy)
      ..lineTo(_p(552, 265).dx, _p(552, 265).dy)
      ..cubicTo(_p(585, 258).dx, _p(585, 258).dy, _p(600, 238).dx,
          _p(600, 238).dy, _p(_G.shellRight, 232).dx, _p(_G.shellRight, 232).dy)
      ..lineTo(_p(_G.shellRight, 388).dx, _p(_G.shellRight, 388).dy)
      ..cubicTo(_p(600, 382).dx, _p(600, 382).dy, _p(585, 362).dx,
          _p(585, 362).dy, _p(552, 355).dx, _p(552, 355).dy)
      ..lineTo(_p(410, 355).dx, _p(410, 355).dy)
      ..cubicTo(_p(380, 362).dx, _p(380, 362).dy, _p(365, 382).dx,
          _p(365, 382).dy, _p(_G.shellLeft, 388).dx, _p(_G.shellLeft, 388).dy)
      ..close();
    canvas.drawPath(body, _fill(palette.fill));
    canvas.drawPath(body, _stroke(palette.ink, 1.8));

    _paintFlange(
        canvas, _G.flangeLeft, _G.flangeLeftRadius, HubGuidePart.pcdLeft);
    _paintFlange(
        canvas, _G.flangeRight, _G.flangeRightRadius, HubGuidePart.pcdRight);
  }

  void _paintFlange(Canvas canvas, double x, double radius, HubGuidePart part) {
    final focus = math.max(_focus(part), _focus(HubGuidePart.spokeHoles));
    final rect = Rect.fromCenter(
      center: _p(x, _G.cy),
      width: _d(30),
      height: _d(radius * 2),
    );
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(_d(13)));
    canvas.drawRRect(
        shape, _fill(_mix(palette.fillDeep, palette.accentContainer, focus)));
    canvas.drawRRect(
        shape, _stroke(_mix(palette.ink, palette.accent, focus), 1.8));
    for (final offset in [-0.72, -0.36, 0.0, 0.36, 0.72]) {
      final hole = _p(x, _G.cy + radius * offset);
      canvas.drawCircle(hole, _d(6.5), _fill(palette.paper));
      canvas.drawCircle(hole, _d(6.5),
          _stroke(_mix(palette.ink, palette.accent, focus), 1.2));
    }
    _register(part, rect);
    _register(HubGuidePart.spokeHoles, rect);
  }

  void _paintRotorInterface(Canvas canvas) {
    final kind = configuration.rotorInterface;
    if (kind == HubGuideRotorInterface.none ||
        kind == HubGuideRotorInterface.unknown) {
      return;
    }
    final focus = _focus(HubGuidePart.rotorMount);
    final edge = _mix(palette.ink, palette.accent, focus);
    final fill = _mix(palette.fillDeep, palette.accentContainer, focus);
    final rect = Rect.fromPoints(_p(220, 222), _p(278, 398));
    if (kind == HubGuideRotorInterface.centerLock) {
      final body = RRect.fromRectAndRadius(rect, Radius.circular(_d(10)));
      canvas.drawRRect(body, _fill(fill));
      canvas.drawRRect(body, _stroke(edge, 1.6));
      for (var i = 0; i < 7; i++) {
        final y = 242 + i * 23.0;
        canvas.drawLine(_p(226, y), _p(244, y + 8), _stroke(edge, 1.1));
      }
    } else {
      final disc = Rect.fromCenter(
          center: _p(247, _G.cy), width: _d(18), height: _d(224));
      final shape = RRect.fromRectAndRadius(disc, Radius.circular(_d(8)));
      canvas.drawRRect(shape, _fill(fill));
      canvas.drawRRect(shape, _stroke(edge, 1.6));
      if (kind == HubGuideRotorInterface.sixBolt) {
        for (final offset in [-72.0, -36.0, 0.0, 36.0, 72.0]) {
          canvas.drawCircle(
              _p(247, _G.cy + offset), _d(4.5), _fill(palette.paper));
          canvas.drawCircle(_p(247, _G.cy + offset), _d(4.5), _stroke(edge, 1));
        }
      }
    }
    _register(HubGuidePart.rotorMount, rect);
  }

  void _paintDriveInterface(Canvas canvas) {
    final kind = configuration.driveInterface;
    if (kind == HubGuideDriveInterface.none ||
        kind == HubGuideDriveInterface.unknown) {
      return;
    }
    final focus = _focus(HubGuidePart.driveReceiver);
    final edge = _mix(palette.ink, palette.accent, focus);
    final fill = _mix(palette.fillDeep, palette.accentContainer, focus);
    final right = kind == HubGuideDriveInterface.bmxDriver ? 755.0 : 810.0;
    final rect = Rect.fromPoints(_p(670, 258), _p(right, 362));
    final body = RRect.fromRectAndRadius(rect, Radius.circular(_d(10)));
    canvas.drawRRect(body, _fill(fill));
    canvas.drawRRect(body, _stroke(edge, 1.7));
    switch (kind) {
      case HubGuideDriveInterface.cassette:
        for (final y in [272.0, 290.0, 310.0, 330.0, 348.0]) {
          canvas.drawLine(_p(682, y), _p(right - 10, y), _stroke(edge, 1));
        }
      case HubGuideDriveInterface.threadedFreewheel:
        _threadMarks(canvas, 684, right - 10, 270, 350, edge);
      case HubGuideDriveInterface.fixedThread:
        _threadMarks(canvas, 684, 758, 270, 350, edge);
        _threadMarks(canvas, 768, right - 8, 278, 342, edge);
      case HubGuideDriveInterface.lockringCog:
        for (var i = 0; i < 6; i++) {
          final x = 688 + i * (right - 702) / 5;
          canvas.drawLine(_p(x, 272), _p(x, 348), _stroke(edge, 1));
        }
        canvas.drawLine(
            _p(right - 13, 265), _p(right - 13, 355), _stroke(edge, 2.2));
      case HubGuideDriveInterface.bmxDriver:
        canvas.drawCircle(_p(716, _G.cy), _d(34), _stroke(edge, 2));
        canvas.drawCircle(_p(716, _G.cy), _d(18), _stroke(edge, 1.2));
      case HubGuideDriveInterface.generic:
      case HubGuideDriveInterface.none:
      case HubGuideDriveInterface.unknown:
        break;
    }
    _register(HubGuidePart.driveReceiver, rect);
  }

  void _threadMarks(Canvas canvas, double left, double right, double top,
      double bottom, Color color) {
    if (right <= left) return;
    for (var i = 0; i < 7; i++) {
      final x = left + (right - left) * i / 6;
      canvas.drawLine(_p(x - 5, bottom), _p(x + 5, top),
          _stroke(color.withValues(alpha: 0.84), 1));
    }
  }

  void _paintBearings(Canvas canvas) {
    final kind = configuration.bearingSystem;
    if (kind == HubGuideBearingSystem.unknown) return;
    final focus = _focus(HubGuidePart.bearings);
    final edge = _mix(palette.ink, palette.accent, focus);
    final fill = _mix(palette.paper, palette.accentContainer, focus);
    for (final x in [372.0, 590.0]) {
      final rect =
          Rect.fromCenter(center: _p(x, _G.cy), width: _d(34), height: _d(70));
      if (kind == HubGuideBearingSystem.sealed ||
          kind == HubGuideBearingSystem.mixed) {
        final ring = RRect.fromRectAndRadius(rect, Radius.circular(_d(8)));
        canvas.drawRRect(ring, _fill(fill));
        canvas.drawRRect(ring, _stroke(edge, 1.4));
        canvas.drawLine(_p(x - 10, 282), _p(x - 10, 338), _stroke(edge, 1));
        canvas.drawLine(_p(x + 10, 282), _p(x + 10, 338), _stroke(edge, 1));
      }
      if (kind == HubGuideBearingSystem.loose ||
          kind == HubGuideBearingSystem.mixed) {
        for (final y in [284.0, 300.0, 320.0, 336.0]) {
          canvas.drawCircle(_p(x, y), _d(4.5), _fill(fill));
          canvas.drawCircle(_p(x, y), _d(4.5), _stroke(edge, 1));
        }
      }
      _register(HubGuidePart.bearings, rect);
    }
  }

  void _paintSideMeasurement(Canvas canvas) {
    if (current == null || current!.isEmpty) return;
    if (_selected(HubGuidePart.old)) {
      _extension(canvas, _p(_G.oldLeft, 342), _p(_G.oldLeft, 510));
      _extension(canvas, _p(_G.oldRight, 342), _p(_G.oldRight, 510));
      _dimension(canvas, _p(_G.oldLeft, 505), _p(_G.oldRight, 505),
          _compact ? 'OLD' : 'Ancho entre apoyos (OLD)', HubGuidePart.old);
      return;
    }
    if (_selected(HubGuidePart.flangeToFlange)) {
      _extension(canvas, _p(_G.flangeLeft, 164), _p(_G.flangeLeft, 116));
      _extension(canvas, _p(_G.flangeRight, 184), _p(_G.flangeRight, 116));
      _dimension(
          canvas,
          _p(_G.flangeLeft, 120),
          _p(_G.flangeRight, 120),
          _compact ? 'Entre lados' : 'Entre los círculos de hoyos',
          HubGuidePart.flangeToFlange);
      return;
    }
    if (_selected(HubGuidePart.centerToLeft)) {
      _extension(canvas, _p(_G.flangeLeft, 164), _p(_G.flangeLeft, 116));
      _dimension(
          canvas,
          _p(_G.flangeLeft, 120),
          _p(_G.centreX, 120),
          _compact ? 'Centro → izq.' : 'Centro → círculo izquierdo',
          HubGuidePart.centerToLeft);
      return;
    }
    if (_selected(HubGuidePart.centerToRight)) {
      _extension(canvas, _p(_G.flangeRight, 184), _p(_G.flangeRight, 116));
      _dimension(
          canvas,
          _p(_G.centreX, 120),
          _p(_G.flangeRight, 120),
          _compact ? 'Centro → der.' : 'Centro → círculo derecho',
          HubGuidePart.centerToRight);
      return;
    }
    if (_selected(HubGuidePart.axleDiameter)) {
      _dimension(canvas, _p(910, 292), _p(910, 328),
          _compact ? 'Ø eje' : 'Diámetro del eje', HubGuidePart.axleDiameter,
          labelOffset: const Offset(48, 0));
      return;
    }
    if (_selected(HubGuidePart.spokeHoles)) {
      final text = spokeHoleCount == null
          ? 'Cantidad total de hoyos'
          : '$spokeHoleCount hoyos totales';
      _callout(canvas, _p(_G.flangeLeft, 202), _p(195, 112), text,
          HubGuidePart.spokeHoles);
      _callout(
          canvas,
          _p(_G.flangeRight, 215),
          _p(805, 112),
          _compact ? 'Ambos lados' : 'Se cuentan en toda la maza',
          HubGuidePart.spokeHoles);
      return;
    }
    if (_selected(HubGuidePart.axleEnds)) {
      _callout(canvas, _p(_G.oldLeft, _G.cy), _p(190, 145), _axleLabel(),
          HubGuidePart.axleEnds);
      return;
    }
    if (_selected(HubGuidePart.axleBody)) {
      _callout(canvas, _p(520, _G.cy), _p(560, 445),
          _compact ? 'Eje' : 'Zona medida del eje', HubGuidePart.axleBody);
      return;
    }
    if (_selected(HubGuidePart.rotorMount)) {
      if (configuration.rotorInterface == HubGuideRotorInterface.none) {
        _status(canvas, 'Sin anclaje de disco');
      } else if (configuration.rotorInterface ==
          HubGuideRotorInterface.unknown) {
        _status(canvas, 'Anclaje de disco sin confirmar');
      } else {
        _callout(canvas, _p(247, 236), _p(172, 126), _rotorLabel(),
            HubGuidePart.rotorMount);
      }
      return;
    }
    if (_selected(HubGuidePart.driveReceiver)) {
      if (configuration.driveInterface == HubGuideDriveInterface.none) {
        _status(canvas, 'Sin montaje para piñón');
      } else if (configuration.driveInterface ==
          HubGuideDriveInterface.unknown) {
        _status(canvas, 'Montaje del piñón sin confirmar');
      } else {
        _callout(canvas, _p(745, 270), _p(800, 132), _driveLabel(),
            HubGuidePart.driveReceiver);
      }
      return;
    }
    if (_selected(HubGuidePart.bearings)) {
      if (configuration.bearingSystem == HubGuideBearingSystem.unknown) {
        _status(canvas, 'Rodamientos sin confirmar');
      } else {
        _callout(canvas, _p(372, 282), _p(250, 138), _bearingLabel(),
            HubGuidePart.bearings);
      }
    }
  }

  String _axleLabel() => switch (configuration.axleMount) {
        HubGuideAxleMount.quickRelease => 'Cierre rápido',
        HubGuideAxleMount.thruAxle => 'Eje pasante',
        HubGuideAxleMount.nutted => 'Eje con tuercas',
        HubGuideAxleMount.femaleBolt => 'Eje hembra con pernos',
        HubGuideAxleMount.generic => 'Sujeción OEM',
        HubGuideAxleMount.unknown => 'Sujeción sin confirmar',
      };

  String _rotorLabel() => switch (configuration.rotorInterface) {
        HubGuideRotorInterface.sixBolt => 'Anclaje de 6 pernos',
        HubGuideRotorInterface.centerLock => 'Anclaje Centerlock',
        HubGuideRotorInterface.generic => 'Anclaje de disco',
        HubGuideRotorInterface.none => 'Sin anclaje de disco',
        HubGuideRotorInterface.unknown => 'Anclaje sin confirmar',
      };

  String _driveLabel() => switch (configuration.driveInterface) {
        HubGuideDriveInterface.cassette => 'Núcleo de cassette',
        HubGuideDriveInterface.threadedFreewheel => 'Rosca para rueda libre',
        HubGuideDriveInterface.fixedThread => 'Rosca para piñón fijo',
        HubGuideDriveInterface.lockringCog => 'Piñón con anillo',
        HubGuideDriveInterface.bmxDriver => 'Núcleo BMX (driver)',
        HubGuideDriveInterface.generic => 'Montaje del piñón',
        HubGuideDriveInterface.none => 'Sin montaje para piñón',
        HubGuideDriveInterface.unknown => 'Montaje sin confirmar',
      };

  String _bearingLabel() => switch (configuration.bearingSystem) {
        HubGuideBearingSystem.sealed => 'Rodamientos sellados',
        HubGuideBearingSystem.loose => 'Bolas sueltas',
        HubGuideBearingSystem.mixed => 'Rodamientos mixtos',
        HubGuideBearingSystem.unknown => 'Rodamientos sin confirmar',
      };

  void _paintFlangeScene(Canvas canvas) {
    final isRight = _selected(HubGuidePart.pcdRight);
    final side = isRight ? 'LADO DERECHO' : 'LADO IZQUIERDO';
    _caption(canvas, _p(500, 58), side);

    final centre = _p(470, 310);
    final outerRadius = _d(190);
    final pcdRadius = _d(144);
    canvas.drawCircle(centre, outerRadius, _fill(palette.fill));
    canvas.drawCircle(centre, outerRadius, _stroke(palette.ink, 1.8));
    canvas.drawCircle(centre, _d(51), _fill(palette.fillDeep));
    canvas.drawCircle(centre, _d(51), _stroke(palette.ink, 1.6));
    canvas.drawCircle(centre, _d(17), _fill(palette.paper));
    canvas.drawCircle(centre, _d(17), _stroke(palette.ink, 1.4));

    final pcdFocus =
        math.max(_focus(HubGuidePart.pcdLeft), _focus(HubGuidePart.pcdRight));
    final holeFocus = _focus(HubGuidePart.spokeHoleDiameter);
    final pcdPaint = _stroke(
        _mix(palette.inkMuted, palette.accent, pcdFocus), 1.2 + pcdFocus);
    _dashedCircle(canvas, centre, pcdRadius, pcdPaint);

    const displayHoleCount = 16;
    Offset? focusedHole;
    for (var i = 0; i < displayHoleCount; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / displayHoleCount;
      final hole = Offset(centre.dx + pcdRadius * math.cos(angle),
          centre.dy + pcdRadius * math.sin(angle));
      final chosen = i == 2;
      final focus = chosen ? holeFocus : pcdFocus;
      canvas.drawCircle(hole, _d(8),
          _fill(_mix(palette.paper, palette.accentContainer, focus)));
      canvas.drawCircle(hole, _d(8),
          _stroke(_mix(palette.ink, palette.accent, focus), 1.2 + focus));
      if (chosen) focusedHole = hole;
    }

    final flangeRect = Rect.fromCircle(center: centre, radius: outerRadius);
    _register(
        isRight ? HubGuidePart.pcdRight : HubGuidePart.pcdLeft, flangeRect);
    _register(HubGuidePart.spokeHoleDiameter, flangeRect);

    if (pcdFocus > 0) {
      const angle = -math.pi / 4;
      final first = Offset(centre.dx + pcdRadius * math.cos(angle),
          centre.dy + pcdRadius * math.sin(angle));
      final second = Offset(centre.dx - pcdRadius * math.cos(angle),
          centre.dy - pcdRadius * math.sin(angle));
      _dimension(
        canvas,
        second,
        first,
        _compact ? 'Ø círculo' : 'Diámetro del círculo de hoyos',
        isRight ? HubGuidePart.pcdRight : HubGuidePart.pcdLeft,
        labelOffset: const Offset(40, -28),
      );
    } else if (holeFocus > 0 && focusedHole != null) {
      _paintHoleDetail(canvas, focusedHole);
    }

    _caption(canvas, _p(470, 556), 'VISTA FRONTAL DEL LADO DE LOS RAYOS');
  }

  void _paintHoleDetail(Canvas canvas, Offset source) {
    final detailCentre = _p(795, 260);
    final radius = _d(58);
    _dashedLine(canvas, source, detailCentre + Offset(-radius, 0),
        _stroke(palette.inkMuted, 1));
    canvas.drawCircle(detailCentre, radius, _fill(palette.paper));
    canvas.drawCircle(detailCentre, radius, _stroke(palette.accent, 2));
    _dimension(
      canvas,
      detailCentre - Offset(radius, 0),
      detailCentre + Offset(radius, 0),
      _compact ? 'Ø' : 'Ø del agujero',
      HubGuidePart.spokeHoleDiameter,
      labelOffset: const Offset(0, -36),
    );
    _register(HubGuidePart.spokeHoleDiameter,
        Rect.fromCircle(center: detailCentre, radius: radius));
  }

  void _dashedCircle(Canvas canvas, Offset centre, double radius, Paint paint) {
    final path = Path()
      ..addOval(Rect.fromCircle(center: centre, radius: radius));
    for (final metric in path.computeMetrics()) {
      var cursor = 0.0;
      while (cursor < metric.length) {
        final end = math.min(cursor + _d(10), metric.length);
        canvas.drawPath(metric.extractPath(cursor, end), paint);
        cursor += _d(17);
      }
    }
  }

  void _extension(Canvas canvas, Offset from, Offset to) {
    canvas.drawLine(
        from, to, _stroke(palette.inkMuted.withValues(alpha: 0.72), 1));
  }

  void _dimension(
      Canvas canvas, Offset start, Offset end, String text, HubGuidePart part,
      {Offset labelOffset = Offset.zero}) {
    final paint = _stroke(palette.accent, 1.8);
    canvas.drawLine(start, end, paint);
    _arrow(canvas, start, end, palette.accent);
    _arrow(canvas, end, start, palette.accent);
    final middle = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2) +
        Offset(_d(labelOffset.dx), _d(labelOffset.dy));
    final labelRect = _label(canvas, middle, text, active: true);
    _register(part, Rect.fromPoints(start, end).expandToInclude(labelRect));
  }

  void _arrow(Canvas canvas, Offset tip, Offset from, Color color) {
    final vector = tip - from;
    if (vector.distance == 0) return;
    final unit = vector / vector.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final length = _d(13);
    final width = _d(4.5);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - unit.dx * length + normal.dx * width,
          tip.dy - unit.dy * length + normal.dy * width)
      ..lineTo(tip.dx - unit.dx * length - normal.dx * width,
          tip.dy - unit.dy * length - normal.dy * width)
      ..close();
    canvas.drawPath(path, _fill(color));
  }

  void _callout(Canvas canvas, Offset source, Offset labelAt, String text,
      HubGuidePart part) {
    final elbow = Offset(labelAt.dx, source.dy);
    final paint = _stroke(palette.accent, 1.5);
    canvas.drawCircle(source, _d(5), _fill(palette.accent));
    canvas.drawLine(source, elbow, paint);
    canvas.drawLine(elbow, labelAt, paint);
    final labelRect = _label(canvas, labelAt, text, active: true);
    _register(
        part, Rect.fromPoints(source, labelAt).expandToInclude(labelRect));
  }

  void _status(Canvas canvas, String text) {
    _label(canvas, _p(500, 118), text, active: true);
  }

  Rect _label(Canvas canvas, Offset centre, String text,
      {required bool active}) {
    final fontSize = _compact ? 10.5 : 13.5;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(
          fontSize: fontSize,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: active ? palette.onAccentContainer : palette.inkMuted,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final horizontal = _d(_compact ? 14 : 18);
    final vertical = _d(_compact ? 8 : 10);
    final rect = Rect.fromCenter(
      center: centre,
      width: painter.width + horizontal * 2,
      height: painter.height + vertical * 2,
    );
    final pill =
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    canvas.drawRRect(
        pill,
        _fill(active
            ? palette.accentContainer
            : palette.fill.withValues(alpha: 0.9)));
    if (active) canvas.drawRRect(pill, _stroke(palette.accent, 1.1));
    painter.paint(
        canvas,
        Offset(rect.center.dx - painter.width / 2,
            rect.center.dy - painter.height / 2));
    return rect;
  }

  void _caption(Canvas canvas, Offset at, String text,
      {Alignment align = Alignment.center}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: labelStyle.copyWith(
          fontSize: _compact ? 9.5 : 11,
          fontWeight: FontWeight.w600,
          letterSpacing: _compact ? 0.2 : 0.5,
          color: palette.inkMuted,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final x = switch (align) {
      Alignment.centerLeft => at.dx,
      Alignment.centerRight => at.dx - painter.width,
      _ => at.dx - painter.width / 2,
    };
    painter.paint(canvas, Offset(x, at.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(_HubGuidePainter old) =>
      old.current != current ||
      old.progress != progress ||
      old.spokeHoleCount != spokeHoleCount ||
      old.configuration != configuration ||
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
    this.configuration = const HubGuideConfiguration(),
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
  final HubGuideConfiguration configuration;
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
              configuration: configuration,
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
  HubGuideConfiguration configuration = const HubGuideConfiguration(),
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
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700)),
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
                        configuration: configuration,
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
