import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../models/bikeshop_models.dart';

/// La imagen de una bici que no tiene foto: un dibujo por tipo, con el cuadro
/// pintado del color que el taller escribió.
///
/// Dueño, 2026-10-02, al aprobar el rediseño del módulo: ninguna de las 480
/// bicis tiene foto, ningún modelo ni marca trae imagen y sólo 6 de 524
/// trabajos tienen fotos. Una foto genérica igual para todas mentía; este
/// dibujo sale de dos datos que ya existen (tipo y color) y nadie tiene que
/// hacer nada para que aparezca. Si la bici sí tiene foto, la foto manda.
class BikeSilhouette extends StatelessWidget {
  const BikeSilhouette({
    super.key,
    required this.bikeType,
    this.colorText,
    this.markers = const [],
    this.semanticLabel,
  });

  final BikeType? bikeType;

  /// El color tal como está registrado («negra/verde», «plmomo con naranjo»).
  final String? colorText;

  /// Números sobre los sistemas (ficha técnica). Vacío en listas.
  final List<BikeSilhouetteMarker> markers;

  /// Sin etiqueta el dibujo es decorativo: la fila ya dice qué bici es.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final read = bikePaintFromText(colorText);
    // En oscuro un cuadro negro se pierde contra el recuadro y se confunde
    // con el cuadro vacío de una bici sin color: se aclara un poco.
    Color lift(Color color) =>
        theme.brightness == Brightness.dark && color.computeLuminance() < 0.06
            ? Color.lerp(color, Colors.white, 0.2)!
            : color;
    final paint = read == null
        ? null
        : BikePaint(
            lift(read.primary),
            read.secondary == null ? null : lift(read.secondary!),
          );
    final drawing = AspectRatio(
      aspectRatio: _BikeShape.viewWidth / _BikeShape.viewHeight,
      child: CustomPaint(
        painter: _BikeSilhouettePainter(
          shape: _BikeShape.forType(bikeType),
          colors: paint,
          markers: markers,
          wheel: roles.faintForeground,
          outline: Color.lerp(
            theme.colorScheme.outlineVariant,
            theme.colorScheme.outline,
            0.55,
          )!,
          hollow: theme.colorScheme.surfaceContainerHigh,
          detail: theme.colorScheme.onSurfaceVariant,
          markerFill: theme.colorScheme.primary,
          markerText: theme.colorScheme.onPrimary,
          markerRing: theme.colorScheme.surfaceContainerHigh,
          textDirection: Directionality.of(context),
        ),
      ),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: drawing);
    return Semantics(image: true, label: label, child: drawing);
  }
}

/// Un número sobre un sistema del dibujo.
class BikeSilhouetteMarker {
  const BikeSilhouetteMarker({required this.anchor, required this.label});

  final BikeSilhouetteAnchor anchor;
  final String label;
}

/// Dónde cae cada sistema en el dibujo de cualquier tipo de bici.
enum BikeSilhouetteAnchor {
  frame,
  drivetrain,
  bottomBracket,
  brakes,
  wheels,
  cockpit
}

/// El color de una bici leído del texto que escribió el taller.
@immutable
class BikePaint {
  const BikePaint(this.primary, [this.secondary]);

  /// Cuadro delantero.
  final Color primary;

  /// Triángulo trasero cuando el texto nombra dos colores.
  final Color? secondary;
}

/// Lee el color de una bici desde texto libre.
///
/// El 2026-10-02 había 360 bicis con color escrito de 84 formas: «negra» y
/// «negro», «azul marino», «negra/verde», «negra con rosado», «plmomo con
/// naranjo», «negro azukl». Se reconoce la palabra (con un error de tipeo de
/// una letra en palabras de cuatro o más) y, si hay dos colores distintos, el
/// segundo pinta el triángulo trasero. Sin color reconocible devuelve null y
/// el dibujo queda con el cuadro vacío, para no confundirlo con una bici gris.
BikePaint? bikePaintFromText(String? text) {
  final words = _normalizeColorText(text)
      .split(RegExp(r'[^a-z]+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return null;

  final found = <Color>[];
  var index = 0;
  while (index < words.length) {
    Color? color;
    var consumed = 1;
    if (index + 1 < words.length) {
      color = _twoWordColors['${words[index]} ${words[index + 1]}'];
      if (color != null) consumed = 2;
    }
    color ??= _singleWordColor(words[index]);
    if (color != null && !found.contains(color)) found.add(color);
    index += consumed;
  }
  if (found.isEmpty) return null;
  return BikePaint(found.first, found.length > 1 ? found[1] : null);
}

String _normalizeColorText(String? value) => (value ?? '')
    .trim()
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ü', 'u')
    .replaceAll('ñ', 'n');

Color? _singleWordColor(String word) {
  final exact = _oneWordColors[word] ??
      (word.length > 3 && word.endsWith('s')
          ? _oneWordColors[word.substring(0, word.length - 1)]
          : null);
  if (exact != null) return exact;
  if (word.length < 4) return null;
  for (final entry in _oneWordColors.entries) {
    if (entry.key.length >= 4 && _withinOneEdit(word, entry.key)) {
      return entry.value;
    }
  }
  return null;
}

/// Una inserción, borrado, cambio o transposición de letras.
bool _withinOneEdit(String a, String b) {
  if (a == b) return true;
  final lengthGap = (a.length - b.length).abs();
  if (lengthGap > 1) return false;
  if (a.length == b.length) {
    final diffs = <int>[
      for (var i = 0; i < a.length; i++)
        if (a.codeUnitAt(i) != b.codeUnitAt(i)) i,
    ];
    if (diffs.length == 1) return true;
    return diffs.length == 2 &&
        diffs[1] == diffs[0] + 1 &&
        a[diffs[0]] == b[diffs[1]] &&
        a[diffs[1]] == b[diffs[0]];
  }
  final longer = a.length > b.length ? a : b;
  final shorter = a.length > b.length ? b : a;
  var i = 0;
  var j = 0;
  var skipped = false;
  while (i < longer.length && j < shorter.length) {
    if (longer.codeUnitAt(i) == shorter.codeUnitAt(j)) {
      i++;
      j++;
    } else {
      if (skipped) return false;
      skipped = true;
      i++;
    }
  }
  return true;
}

const _black = Color(0xFF25282D);
const _grey = Color(0xFF8D939B);
const _lead = Color(0xFF7B8087);
const _graphite = Color(0xFF4A4F57);
const _white = Color(0xFFF6F6F3);
const _cream = Color(0xFFE9DFC8);
const _blue = Color(0xFF2F5FB3);
const _navy = Color(0xFF24365F);
const _electricBlue = Color(0xFF2D6BF0);
const _skyBlue = Color(0xFF6BB8E6);
const _teal = Color(0xFF2AB3B8);
const _aqua = Color(0xFF4DB6A4);
const _red = Color(0xFFC9352B);
const _wine = Color(0xFF7A1F2B);
const _green = Color(0xFF2E8B57);
const _darkGreen = Color(0xFF2E5E3E);
const _lime = Color(0xFF9BCB2C);
const _yellow = Color(0xFFE9C21A);
const _gold = Color(0xFFC9A23A);
const _orange = Color(0xFFE8742A);
const _pink = Color(0xFFE58FB0);
const _fuchsia = Color(0xFFD6338A);
const _purple = Color(0xFF6E4AA8);
const _lilac = Color(0xFFA48AD4);
const _brown = Color(0xFF7A5230);
const _chrome = Color(0xFFB9C0C8);
const _copper = Color(0xFFB06A3B);

const _twoWordColors = <String, Color>{
  'azul marino': _navy,
  'azul electrico': _electricBlue,
  'azul cromado': _blue,
  'verde agua': _aqua,
  'verde oscuro': _darkGreen,
  'verde militar': _darkGreen,
  'verde limon': _lime,
  'rojo vino': _wine,
  'gris oscuro': _graphite,
  'gris claro': _chrome,
};

const _oneWordColors = <String, Color>{
  'negro': _black,
  'negra': _black,
  'gris': _grey,
  'plomo': _lead,
  'grafito': _graphite,
  'blanco': _white,
  'blanca': _white,
  'crema': _cream,
  'beige': _cream,
  'hueso': _cream,
  'azul': _blue,
  'celeste': _skyBlue,
  'cyan': _teal,
  'turquesa': _teal,
  'calipso': _teal,
  'rojo': _red,
  'roja': _red,
  'burdeo': _wine,
  'granate': _wine,
  'vino': _wine,
  'verde': _green,
  'oliva': _darkGreen,
  'lima': _lime,
  'fluor': _lime,
  'amarillo': _yellow,
  'amarilla': _yellow,
  'dorado': _gold,
  'dorada': _gold,
  'naranja': _orange,
  'naranjo': _orange,
  'anaranjado': _orange,
  'rosa': _pink,
  'rosado': _pink,
  'rosada': _pink,
  'fucsia': _fuchsia,
  'morado': _purple,
  'morada': _purple,
  'violeta': _purple,
  'purpura': _purple,
  'lila': _lilac,
  'cafe': _brown,
  'marron': _brown,
  'cromado': _chrome,
  'cromada': _chrome,
  'plateado': _chrome,
  'plateada': _chrome,
  'plata': _chrome,
  'aluminio': _chrome,
  'cobre': _copper,
  'bronce': _copper,
  // Verde, amarillo y rojo: la escribió así un cliente y se reconoce.
  'jamaiquina': _green,
  'rasta': _green,
};

/// Geometría de cada tipo en un lienzo de 120 × 76.
class _BikeShape {
  const _BikeShape({
    required this.rearWheel,
    required this.frontWheel,
    required this.wheelRadius,
    required this.tire,
    required this.frame,
    required this.rear,
    required this.fork,
    required this.forkWidth,
    required this.bars,
    required this.saddle,
    required this.bottomBracket,
    this.extra = const [],
    this.extraWidth = 1.6,
    this.fenders = const [],
    required this.anchors,
  });

  static const double viewWidth = 120;
  static const double viewHeight = 76;

  final Offset rearWheel;
  final Offset frontWheel;
  final double wheelRadius;
  final double tire;
  final List<List<Offset>> frame;
  final List<List<Offset>> rear;
  final List<Offset> fork;
  final double forkWidth;
  final List<List<Offset>> bars;
  final List<Offset> saddle;
  final Offset bottomBracket;
  final List<List<Offset>> extra;
  final double extraWidth;
  final List<({Offset center, double startAngle, double sweep})> fenders;
  final Map<BikeSilhouetteAnchor, Offset> anchors;

  static _BikeShape forType(BikeType? type) => switch (type) {
        BikeType.mountain => _fullSuspension,
        BikeType.road => _road,
        BikeType.gravel => _gravel,
        BikeType.hybrid || BikeType.other || null => _hybrid,
        BikeType.electric => _electric,
        BikeType.bmx => _bmx,
        BikeType.folding => _folding,
        BikeType.cruiser => _cruiser,
        BikeType.paseo => _paseo,
        BikeType.mountainHardtail => _hardtail,
      };
}

const _standardAnchors = <BikeSilhouetteAnchor, Offset>{
  BikeSilhouetteAnchor.frame: Offset(66, 15),
  BikeSilhouetteAnchor.drivetrain: Offset(27, 37),
  BikeSilhouetteAnchor.bottomBracket: Offset(56, 64),
  BikeSilhouetteAnchor.brakes: Offset(104, 43),
  BikeSilhouetteAnchor.wheels: Offset(112, 64),
  BikeSilhouetteAnchor.cockpit: Offset(91, 7),
};

const _hardtail = _BikeShape(
  rearWheel: Offset(27, 51),
  frontWheel: Offset(93, 51),
  wheelRadius: 21,
  tire: 2.6,
  frame: [
    [Offset(56, 53), Offset(83, 31)],
    [Offset(50, 23), Offset(81, 22), Offset(83, 31)],
    [Offset(56, 53), Offset(50, 23), Offset(49, 15)],
  ],
  rear: [
    [Offset(27, 51), Offset(56, 53)],
    [Offset(27, 51), Offset(50, 23)],
  ],
  fork: [Offset(83, 29), Offset(93, 51)],
  forkWidth: 3.6,
  bars: [
    [Offset(81, 22), Offset(83, 15), Offset(90, 14)],
    [Offset(86, 13), Offset(97, 15)],
  ],
  saddle: [Offset(42, 14), Offset(55, 14)],
  bottomBracket: Offset(56, 53),
  anchors: _standardAnchors,
);

const _fullSuspension = _BikeShape(
  rearWheel: Offset(27, 51),
  frontWheel: Offset(93, 51),
  wheelRadius: 21,
  tire: 2.8,
  frame: [
    [
      Offset(57, 52),
      Offset(83, 31),
      Offset(81, 22),
      Offset(53, 26),
      Offset(57, 52)
    ],
    [Offset(53, 26), Offset(51, 15)],
  ],
  rear: [
    [Offset(27, 51), Offset(57, 50)],
    [Offset(27, 51), Offset(45, 34), Offset(53, 37)],
  ],
  fork: [Offset(83, 29), Offset(93, 51)],
  forkWidth: 4,
  bars: [
    [Offset(81, 22), Offset(83, 15), Offset(90, 14)],
    [Offset(86, 13), Offset(97, 15)],
  ],
  saddle: [Offset(44, 14), Offset(57, 14)],
  bottomBracket: Offset(57, 52),
  extra: [
    [Offset(48, 35), Offset(60, 43)],
  ],
  extraWidth: 3.4,
  anchors: _standardAnchors,
);

const _road = _BikeShape(
  rearWheel: Offset(27, 51),
  frontWheel: Offset(93, 51),
  wheelRadius: 22,
  tire: 1.6,
  frame: [
    [
      Offset(56, 53),
      Offset(84, 27),
      Offset(83, 21),
      Offset(50, 22),
      Offset(56, 53)
    ],
    [Offset(50, 22), Offset(49, 15)],
  ],
  rear: [
    [Offset(27, 51), Offset(56, 53)],
    [Offset(27, 51), Offset(50, 22)],
  ],
  fork: [Offset(84, 26), Offset(93, 51)],
  forkWidth: 2.2,
  bars: [
    [
      Offset(83, 21),
      Offset(85, 16),
      Offset(92, 15),
      Offset(97, 16),
      Offset(98, 20),
      Offset(97, 23),
      Offset(94, 24)
    ],
  ],
  saddle: [Offset(43, 14), Offset(55, 14)],
  bottomBracket: Offset(56, 53),
  anchors: _standardAnchors,
);

const _gravel = _BikeShape(
  rearWheel: Offset(27, 51),
  frontWheel: Offset(93, 51),
  wheelRadius: 22,
  tire: 2.8,
  frame: [
    [
      Offset(56, 53),
      Offset(84, 27),
      Offset(83, 21),
      Offset(50, 23),
      Offset(56, 53)
    ],
    [Offset(50, 23), Offset(49, 15)],
  ],
  rear: [
    [Offset(27, 51), Offset(56, 53)],
    [Offset(27, 51), Offset(50, 23)],
  ],
  fork: [Offset(84, 26), Offset(93, 51)],
  forkWidth: 2.6,
  bars: [
    [
      Offset(83, 21),
      Offset(85, 16),
      Offset(92, 15),
      Offset(98, 16),
      Offset(99, 21),
      Offset(98, 25),
      Offset(96, 26)
    ],
  ],
  saddle: [Offset(43, 14), Offset(55, 14)],
  bottomBracket: Offset(56, 53),
  anchors: _standardAnchors,
);

const _hybrid = _BikeShape(
  rearWheel: Offset(27, 51),
  frontWheel: Offset(93, 51),
  wheelRadius: 22,
  tire: 2,
  frame: [
    [
      Offset(56, 53),
      Offset(83, 29),
      Offset(82, 22),
      Offset(50, 23),
      Offset(56, 53)
    ],
    [Offset(50, 23), Offset(49, 15)],
  ],
  rear: [
    [Offset(27, 51), Offset(56, 53)],
    [Offset(27, 51), Offset(50, 23)],
  ],
  fork: [Offset(83, 28), Offset(93, 51)],
  forkWidth: 2.4,
  bars: [
    [Offset(82, 22), Offset(84, 15), Offset(90, 14)],
    [Offset(87, 14), Offset(97, 14)],
  ],
  saddle: [Offset(42, 14), Offset(55, 14)],
  bottomBracket: Offset(56, 53),
  anchors: _standardAnchors,
);

const _electric = _BikeShape(
  rearWheel: Offset(27, 51),
  frontWheel: Offset(93, 51),
  wheelRadius: 21,
  tire: 2.8,
  frame: [
    [Offset(56, 53), Offset(83, 31)],
    [Offset(50, 23), Offset(81, 22), Offset(83, 31)],
    [Offset(56, 53), Offset(50, 23), Offset(49, 15)],
  ],
  rear: [
    [Offset(27, 51), Offset(56, 53)],
    [Offset(27, 51), Offset(50, 23)],
  ],
  fork: [Offset(83, 29), Offset(93, 51)],
  forkWidth: 3.6,
  bars: [
    [Offset(81, 22), Offset(83, 15), Offset(90, 14)],
    [Offset(86, 13), Offset(97, 15)],
  ],
  saddle: [Offset(42, 14), Offset(55, 14)],
  bottomBracket: Offset(56, 53),
  // La batería sobre el tubo diagonal y el motor central.
  extra: [
    [Offset(61, 46), Offset(75, 34)],
    [Offset(52, 54), Offset(60, 54)],
  ],
  extraWidth: 6.5,
  anchors: _standardAnchors,
);

const _bmx = _BikeShape(
  rearWheel: Offset(32, 56),
  frontWheel: Offset(86, 56),
  wheelRadius: 15,
  tire: 3,
  frame: [
    [
      Offset(56, 55),
      Offset(78, 38),
      Offset(77, 33),
      Offset(52, 36),
      Offset(56, 55)
    ],
    [Offset(52, 36), Offset(51, 30)],
  ],
  rear: [
    [Offset(32, 56), Offset(56, 55)],
    [Offset(32, 56), Offset(52, 36)],
  ],
  fork: [Offset(78, 36), Offset(86, 56)],
  forkWidth: 3,
  bars: [
    [Offset(77, 33), Offset(79, 23), Offset(86, 23)],
    [Offset(80, 20), Offset(91, 21)],
  ],
  saddle: [Offset(45, 29), Offset(56, 29)],
  bottomBracket: Offset(56, 55),
  anchors: {
    BikeSilhouetteAnchor.frame: Offset(64, 27),
    BikeSilhouetteAnchor.drivetrain: Offset(32, 44),
    BikeSilhouetteAnchor.bottomBracket: Offset(56, 66),
    BikeSilhouetteAnchor.brakes: Offset(96, 47),
    BikeSilhouetteAnchor.wheels: Offset(102, 64),
    BikeSilhouetteAnchor.cockpit: Offset(89, 13),
  },
);

const _folding = _BikeShape(
  rearWheel: Offset(34, 57),
  frontWheel: Offset(88, 57),
  wheelRadius: 14,
  tire: 2.4,
  frame: [
    [Offset(40, 55), Offset(62, 52), Offset(84, 41)],
    [Offset(62, 52), Offset(57, 22)],
  ],
  rear: [
    [Offset(34, 57), Offset(40, 55)],
    [Offset(34, 57), Offset(46, 47)],
  ],
  fork: [Offset(85, 41), Offset(88, 57)],
  forkWidth: 2.4,
  bars: [
    [Offset(85, 41), Offset(87, 13)],
    [Offset(81, 13), Offset(93, 13)],
  ],
  saddle: [Offset(51, 21), Offset(63, 21)],
  bottomBracket: Offset(60, 53),
  anchors: {
    BikeSilhouetteAnchor.frame: Offset(72, 38),
    BikeSilhouetteAnchor.drivetrain: Offset(34, 45),
    BikeSilhouetteAnchor.bottomBracket: Offset(60, 65),
    BikeSilhouetteAnchor.brakes: Offset(99, 50),
    BikeSilhouetteAnchor.wheels: Offset(103, 66),
    BikeSilhouetteAnchor.cockpit: Offset(96, 9),
  },
);

const _cruiser = _BikeShape(
  rearWheel: Offset(27, 52),
  frontWheel: Offset(95, 52),
  wheelRadius: 21,
  tire: 3.6,
  frame: [
    [Offset(56, 54), Offset(64, 47), Offset(74, 40), Offset(85, 33)],
    [
      Offset(50, 27),
      Offset(62, 24),
      Offset(74, 24),
      Offset(83, 26),
      Offset(85, 33)
    ],
    [Offset(56, 54), Offset(50, 27), Offset(49, 19)],
  ],
  rear: [
    [Offset(27, 52), Offset(56, 54)],
    [Offset(27, 52), Offset(50, 27)],
  ],
  fork: [Offset(85, 30), Offset(95, 52)],
  forkWidth: 3,
  bars: [
    [
      Offset(83, 26),
      Offset(84, 18),
      Offset(89, 15),
      Offset(95, 16),
      Offset(99, 19)
    ],
  ],
  saddle: [Offset(41, 18), Offset(55, 18)],
  bottomBracket: Offset(56, 54),
  anchors: _standardAnchors,
);

const _paseo = _BikeShape(
  rearWheel: Offset(27, 51),
  frontWheel: Offset(93, 51),
  wheelRadius: 21,
  tire: 2.2,
  frame: [
    [
      Offset(56, 53),
      Offset(60, 44),
      Offset(70, 35),
      Offset(83, 29),
      Offset(82, 21)
    ],
    [Offset(56, 53), Offset(51, 24), Offset(50, 16)],
  ],
  rear: [
    [Offset(27, 51), Offset(56, 53)],
    [Offset(27, 51), Offset(51, 25)],
  ],
  fork: [Offset(83, 28), Offset(93, 51)],
  forkWidth: 2.4,
  bars: [
    [Offset(82, 21), Offset(83, 15), Offset(88, 12), Offset(95, 15)],
  ],
  saddle: [Offset(43, 15), Offset(56, 15)],
  bottomBracket: Offset(56, 53),
  // Canasto adelante.
  extra: [
    [
      Offset(94, 16),
      Offset(106, 16),
      Offset(104, 25),
      Offset(96, 25),
      Offset(94, 16)
    ],
  ],
  fenders: [
    (center: Offset(27, 51), startAngle: 3.36, sweep: 1.5),
    (center: Offset(93, 51), startAngle: 4.21, sweep: 1.5),
  ],
  anchors: _standardAnchors,
);

class _BikeSilhouettePainter extends CustomPainter {
  _BikeSilhouettePainter({
    required this.shape,
    required this.colors,
    required this.markers,
    required this.wheel,
    required this.outline,
    required this.hollow,
    required this.detail,
    required this.markerFill,
    required this.markerText,
    required this.markerRing,
    required this.textDirection,
  });

  final _BikeShape shape;
  final BikePaint? colors;
  final List<BikeSilhouetteMarker> markers;
  final Color wheel;
  final Color outline;
  final Color hollow;
  final Color detail;
  final Color markerFill;
  final Color markerText;
  final Color markerRing;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _BikeShape.viewWidth;
    canvas.save();
    canvas.scale(scale);
    // Un dibujo chico necesita trazos más gruesos para leerse.
    final weight = size.width < 90 ? 1.45 : (size.width < 160 ? 1.15 : 1.0);

    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * weight
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void polyline(List<Offset> points, Paint brush) {
      if (points.length < 2) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, brush);
    }

    for (final fender in shape.fenders) {
      canvas.drawArc(
        Rect.fromCircle(center: fender.center, radius: shape.wheelRadius + 2.4),
        fender.startAngle,
        fender.sweep,
        false,
        stroke(detail, 1.4),
      );
    }

    final tire = stroke(wheel, shape.tire);
    canvas.drawCircle(shape.rearWheel, shape.wheelRadius, tire);
    canvas.drawCircle(shape.frontWheel, shape.wheelRadius, tire);

    final frameOutline = stroke(outline, 4.6);
    for (final segment in [...shape.frame, ...shape.rear]) {
      polyline(segment, frameOutline);
    }
    final main = colors?.primary ?? hollow;
    final rearColor = colors?.secondary ?? main;
    for (final segment in shape.rear) {
      polyline(segment, stroke(rearColor, 2.8));
    }
    for (final segment in shape.frame) {
      polyline(segment, stroke(main, 2.8));
    }

    polyline(shape.fork, stroke(wheel, shape.forkWidth));
    for (final segment in shape.extra) {
      polyline(segment, stroke(detail, shape.extraWidth));
    }
    for (final segment in shape.bars) {
      polyline(segment, stroke(detail, 1.8));
    }
    polyline(shape.saddle, stroke(detail, 2.8));
    canvas.drawCircle(shape.bottomBracket, 3.4, stroke(wheel, 1.4));

    for (final marker in markers) {
      final center = shape.anchors[marker.anchor];
      if (center == null) continue;
      canvas.drawCircle(center, 5.4, Paint()..color = markerRing);
      canvas.drawCircle(center, 4.6, Paint()..color = markerFill);
      final text = TextPainter(
        text: TextSpan(
          text: marker.label,
          style: TextStyle(
            color: markerText,
            fontSize: 5.4,
            fontWeight: FontWeight.w700,
            fontFamily: 'Barlow',
            height: 1,
          ),
        ),
        textDirection: textDirection,
      )..layout();
      text.paint(
        canvas,
        center - Offset(text.width / 2, text.height / 2),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BikeSilhouettePainter old) =>
      old.shape != shape ||
      old.colors?.primary != colors?.primary ||
      old.colors?.secondary != colors?.secondary ||
      old.markers != markers ||
      old.wheel != wheel ||
      old.outline != outline ||
      old.hollow != hollow ||
      old.detail != detail ||
      old.markerFill != markerFill;
}
