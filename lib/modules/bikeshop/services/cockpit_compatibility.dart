import '../../../shared/models/product_compatibility.dart';
import '../config/cockpit_canonical_data.dart';
import '../models/bikeshop_models.dart';

/// Lo que una pieza de dirección o cockpit dice contra la ficha de la bici
/// al buscarla para un trabajo (lienzo «Bicicletas — lo que falta», «Y valida
/// a la persona», 2026-10-02): se compara con la ficha, sin que nadie mida
/// nada, y se dice la razón. La ficha se llena con lo que el taller instala
/// (20261002170000); estas reglas son las de la wiki (`direccion.md`,
/// `manubrio-potencia-y-tija.md`):
///
/// * la potencia aprieta el manubrio por su centro: con laina, un manubrio
///   más delgado en una potencia más grande, nunca al revés; y aprieta el tubo
///   de la horquilla por arriba (un cónico es 1⅛″ ahí);
/// * manillas, mandos y puños calzan por la zona de mandos (22,2 plano, 23,8
///   ruta), y no hay laina que los cambie;
/// * una tija más delgada entra con casquillo, una más gruesa no;
/// * una horquilla cónica no entra en una dirección recta de 1⅛″; una recta
///   en un cuadro cónico va con la taza de abajo reductora.
///
/// Nulo si la pieza no es de estas familias o si ni la pieza ni la ficha
/// dicen la medida: «no sé» no es «no calza».
ProductCompatibilityAssessment? assessCockpitCompatibility({
  required String? templateKey,
  required Map<String, dynamic> specValues,
  required Map<String, dynamic> technicalValues,
  BikeType? bikeType,
}) {
  final controls = _measure(technicalValues[kControlsBarDiameterKey]);
  final clamp = _measure(technicalValues[kHandlebarClampKey]);
  switch (templateKey?.trim().toLowerCase()) {
    case 'shifter':
    case 'brake_lever':
    case 'grip':
      final product = _measure(templateKey == 'grip'
          ? specValues['grip_bar_nominal_diameter_mm']
          : specValues['handlebar_clamp_mm']);
      if (product == null) return null;
      final piece = switch (templateKey) {
        'shifter' => 'Este mando',
        'brake_lever' => 'Esta manilla',
        _ => 'Estos puños',
      };
      if (controls != null) {
        if (controls == product) {
          return ProductCompatibilityAssessment.compatible(
            detail: 'Calza en la zona de mandos de '
                '${cockpitMillimeters(controls)} de la ficha.',
          );
        }
        return ProductCompatibilityAssessment.incompatible(
          detail: '$piece es para un manubrio de '
              '${cockpitMillimeters(product)} y en la ficha la zona de mandos '
              'es de ${cockpitMillimeters(controls)}: no hay laina que lo '
              'cambie.',
        );
      }
      final suggested = suggestedControlsBarDiameterForBikeType(bikeType);
      if (suggested != null && suggested != product) {
        return ProductCompatibilityAssessment.caution(
          detail: '$piece es para un manubrio de '
              '${cockpitMillimeters(product)}; por el tipo de bici el suyo '
              'sería de ${cockpitMillimeters(suggested)}. Confirma el '
              'manubrio.',
          sortPriority: 38,
        );
      }
      return null;
    case 'stem':
      final barClamp = _measure(specValues['bar_clamp_diameter_mm']);
      final steererClamp =
          _measure(specValues['stem_steerer_clamp_diameter_mm']);
      final steerer = kSteererTopDiameterMm[
          technicalValues[kSteererFitKey]?.toString().trim()];
      if (steererClamp != null && steerer != null) {
        if (steererClamp < steerer) {
          return ProductCompatibilityAssessment.incompatible(
            detail: 'Esta potencia aprieta un tubo de '
                '${cockpitMillimeters(steererClamp)} y el de la horquilla es '
                'de ${cockpitMillimeters(steerer)} arriba.',
          );
        }
      }
      if (barClamp != null && clamp != null && barClamp < clamp) {
        return ProductCompatibilityAssessment.incompatible(
          detail: 'Esta potencia aprieta un manubrio de '
              '${cockpitMillimeters(barClamp)} y el de la ficha es de '
              '${cockpitMillimeters(clamp)}: no entra.',
        );
      }
      final notes = [
        if (steererClamp != null && steerer != null && steererClamp > steerer)
          'aprieta el tubo de ${cockpitMillimeters(steerer)} con laina',
        if (barClamp != null && clamp != null && barClamp > clamp)
          'aprieta el manubrio de ${cockpitMillimeters(clamp)} con laina',
      ];
      if (notes.isNotEmpty) {
        return ProductCompatibilityAssessment.caution(
          detail: 'Calza si ${notes.join(' y ')}.',
          sortPriority: 32,
        );
      }
      if ((barClamp != null && clamp != null) ||
          (steererClamp != null && steerer != null)) {
        return const ProductCompatibilityAssessment.compatible(
          detail: 'Mismas medidas que la ficha.',
        );
      }
      return null;
    case 'handlebar':
      final barClamp = _measure(specValues['bar_clamp_diameter_mm']);
      final barControls = _measure(specValues['grip_area_diameter_mm']);
      final notes = [
        if (barClamp != null && clamp != null && barClamp != clamp)
          'la potencia de la ficha es de ${cockpitMillimeters(clamp)} y este '
              'manubrio de ${cockpitMillimeters(barClamp)}'
              '${barClamp < clamp ? ' (va con laina)' : ': cambia la potencia'}',
        if (barControls != null && controls != null && barControls != controls)
          'su zona de mandos es de ${cockpitMillimeters(barControls)} y la de '
              'la ficha de ${cockpitMillimeters(controls)}: cambian manillas, '
              'mandos y puños',
      ];
      if (notes.isNotEmpty) {
        return ProductCompatibilityAssessment.caution(
          detail: '${notes.join('; ')}.'.replaceFirstMapped(
              RegExp(r'^.'), (match) => match[0]!.toUpperCase()),
          sortPriority: 34,
        );
      }
      if ((barClamp != null && clamp != null) ||
          (barControls != null && controls != null)) {
        return const ProductCompatibilityAssessment.compatible(
          detail: 'Mismas medidas que la ficha.',
        );
      }
      return null;
    case 'seatpost':
      final kind = specValues['seatpost_kind']?.toString();
      if (kind == 'Suplemento (shim)') return null;
      final product = _measure(specValues['seatpost_diameter_mm']);
      final bike = _measure(technicalValues[kSeatpostDiameterKey]);
      if (product == null || bike == null) return null;
      if (product == bike) {
        return ProductCompatibilityAssessment.compatible(
          detail: 'Tija de ${cockpitMillimeters(bike)}, la de la ficha.',
        );
      }
      if (product > bike) {
        return ProductCompatibilityAssessment.incompatible(
          detail: 'Esta tija es de ${cockpitMillimeters(product)} y la bici '
              'usa ${cockpitMillimeters(bike)}: no entra.',
        );
      }
      return ProductCompatibilityAssessment.caution(
        detail: 'Esta tija es de ${cockpitMillimeters(product)} y la bici usa '
            '${cockpitMillimeters(bike)}: entra con un casquillo de '
            '${cockpitMillimeters(product)} a ${cockpitMillimeters(bike)}.',
        sortPriority: 32,
      );
    case 'fork':
      final product = _steererCode(specValues['steerer_fit']?.toString());
      // Sólo un código de la hoja es un dato: «unknown», «desconocido» o un
      // código viejo son «no sé», no «no calza» (revisión de Codex,
      // 2026-10-02).
      final bike = technicalValues[kSteererFitKey]?.toString().trim();
      if (product == null || !kSteererFitLabels.containsKey(bike)) return null;
      if (product == bike) {
        return ProductCompatibilityAssessment.compatible(
          detail: 'Tubo ${kSteererFitLabels[bike] ?? bike}, el de la ficha.',
        );
      }
      if (product == 'straight_1_1_8' && bike == 'tapered_1_1_8_1_5') {
        return const ProductCompatibilityAssessment.caution(
          detail: 'Horquilla recta de 1⅛″ en un cuadro cónico: va con la taza '
              'de abajo reductora (por ejemplo ZS56/28.6) y su pista de '
              'corona de 1⅛″.',
          sortPriority: 32,
        );
      }
      return ProductCompatibilityAssessment.incompatible(
        detail: 'Esta horquilla es de tubo '
            '${kSteererFitLabels[product] ?? product} y la dirección de la '
            'bici es para ${kSteererFitLabels[bike] ?? bike}.',
      );
  }
  return null;
}

/// Si la ficha dice algo de dirección o cockpit, o el tipo de bici sugiere
/// la zona de mandos: hay con qué comparar una pieza de esas familias.
bool cockpitFactsKnown(
  Map<String, dynamic> technicalValues, {
  BikeType? bikeType,
}) =>
    suggestedControlsBarDiameterForBikeType(bikeType) != null ||
    kSteererFitLabels
        .containsKey(technicalValues[kSteererFitKey]?.toString().trim()) ||
    [
      kHandlebarClampKey,
      kControlsBarDiameterKey,
      kSeatpostDiameterKey,
    ].any((key) => '${technicalValues[key] ?? ''}'.trim().isNotEmpty);

/// La medida de la ficha de la bici o del producto: 22.2, «22.2» o «22,2».
double? _measure(Object? raw) {
  final value = raw is num
      ? raw.toDouble()
      : double.tryParse('${raw ?? ''}'.trim().replaceAll(',', '.'));
  return value == null || value <= 0 ? null : value;
}

/// El código de la ficha para lo que dice `steerer_fit` del inventario: el
/// mismo mapa de su fila en `bike_fact_spec_links`.
String? _steererCode(String? text) => switch (text?.trim()) {
      '1" (25.4 mm)' => 'straight_1',
      '1 1/8" (28.6 mm)' => 'straight_1_1_8',
      '1 1/4" (31.8 mm)' => 'straight_1_1_4',
      '1.5" (38.1 mm)' => 'straight_1_5',
      'Tapered 1 1/8" – 1.5"' || 'Tapered 1 1/8" - 1.5"' => 'tapered_1_1_8_1_5',
      _ => null,
    };
