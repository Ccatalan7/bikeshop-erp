import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/brake_canonical_data.dart';
import '../config/cockpit_canonical_data.dart';
import '../config/drivetrain_canonical_data.dart';
import '../config/wheel_canonical_data.dart';
import '../models/bikeshop_models.dart';
import 'bike_technical_fact_patch.dart' show kBikeWheelSizeFactKey;

/// Una fila de `bike_fact_spec_links`: la relación única concepto + posición
/// + familia entre la ficha técnica de un repuesto y la ficha de la bici
/// (20260928100000, 20260928110000, 20260928120000, 20260928130000,
/// 20260928140000).
/// `rotor_diameter_mm_value` en la rueda trasera es `rearRotorSizeMm`, y un
/// rotor pide freno de disco; el `bead_seat_diameter_mm` de un neumático es el
/// BSD de su rueda y tiene que calzar con ella; las estrías de un cassette (o
/// la familia de un piñón de rosca de dos o más coronas) dicen el driver
/// trasero, que tiene que calzar, y sus piñones sólo se revisan contra la
/// transmisión; una maza pone el driver trasero y el anclaje del rotor de su
/// rueda, y sus perforaciones sólo se revisan contra la rueda que queda; una
/// llanta cambia el BSD y las perforaciones de su rueda, si calza con su
/// neumático, su maza y su Enrayado. El servidor la usa al terminar el
/// trabajo; aquí, para mostrar el cambio en la línea. Ningún módulo tiene la
/// suya.
class BikeFactSpecLink {
  const BikeFactSpecLink({
    required this.specKey,
    required this.position,
    required this.bikeFactKey,
    required this.componentLabel,
    this.componentArticle = 'el',
    this.unit,
    this.requiresFactKey,
    this.requiresFactValues = const {},
    this.minValue,
    this.maxValue,
    this.templateKey,
    this.mustFit = false,
    this.isCheck = false,
    this.valueMap = const {},
    this.constantValue,
    this.fits = const {},
    this.productConditionKey,
    this.productConditionMin,
    this.productConditionMax,
    this.productConditionValues,
    this.productConditionMissingOk = false,
    this.valueDecimals = 0,
  });

  /// El campo de la ficha técnica del producto, o `_family` cuando lo dice
  /// la familia del producto ([constantValue]).
  final String specKey;
  final BikeMemoryLocation position;
  final String bikeFactKey;

  /// «rotor trasero», «rueda trasera», «driver trasero»: cómo se nombra en el
  /// taller la pieza de esa posición, y su artículo.
  final String componentLabel;
  final String componentArticle;
  final String? unit;

  /// La familia de producto de la fila (`tire`, `cassette`, `freewheel`): una
  /// llanta también dice `bead_seat_diameter_mm` y no usa la fila del
  /// neumático. Nula, vale para cualquiera.
  final String? templateKey;

  /// `on_mismatch = 'conflict'`: la pieza tiene que calzar con lo que la
  /// bici ya es (un neumático con su rueda, un cassette con su driver); no la
  /// cambia. Si no, es un cambio (un rotor de otro diámetro).
  final bool mustFit;

  /// `on_mismatch = 'check'`: sólo se revisa (los piñones de un cassette
  /// contra la transmisión); nunca se escribe ni se marca.
  final bool isCheck;

  /// Del valor de la ficha técnica del producto al código de la ficha de la
  /// bici («Shimano HG spline S (7v)» → `shimano_hg`). Un valor que no está
  /// no se anota.
  final Map<String, String> valueMap;

  /// Lo que la familia del producto ya dice: un piñón de rosca es rueda libre
  /// roscada.
  final String? constantValue;

  /// Además del mismo código, con qué códigos de la bici calza sin cambiarla:
  /// un cassette HG en un núcleo HG Road 11 con separador.
  final Map<String, Set<String>> fits;

  /// La fila vale sólo si el producto dice [productConditionKey] entre
  /// [productConditionMin] y [productConditionMax]: un piñón de rosca de 2 a
  /// 14 coronas (uno de una puede ser fijo; 99 es un error de la ficha). O,
  /// con [productConditionValues], uno de esos textos: una maza trasera o
  /// universal (un juego no instala: una línea es una rueda); sin decirlo,
  /// vale si [productConditionMissingOk] (la rueda la eligió el mecánico).
  final String? productConditionKey;
  final num? productConditionMin;
  final num? productConditionMax;
  final Set<String>? productConditionValues;
  final bool productConditionMissingOk;

  /// Decimales que acepta la medida (31,8 mm de una abrazadera: 1); 0, una
  /// medida entera (20261002170000).
  final int valueDecimals;

  /// Una pieza de toda la bici (horquilla, manubrio, tija): va sin rueda.
  bool get isBikeWide => position == BikeMemoryLocation.none;

  /// Lo que el producto cumple de la condición de la fila
  /// (`bike_fact_product_condition_met_internal`).
  bool productMeetsCondition(Map<String, dynamic> specValues) {
    final conditionKey = productConditionKey;
    if (conditionKey == null) return true;
    final values = productConditionValues;
    if (values != null) {
      final text = specValues[conditionKey]?.toString();
      if (text == null || text.trim().isEmpty) {
        return productConditionMissingOk;
      }
      return values.contains(text);
    }
    final measured = _wholeMeasure(specValues[conditionKey]);
    return measured != null &&
        measured >= (productConditionMin ?? 0) &&
        (productConditionMax == null || measured <= productConditionMax!);
  }

  bool appliesTo(String? productTemplateKey) =>
      templateKey == null ||
      templateKey == productTemplateKey?.trim().toLowerCase();

  /// Un código de la ficha (driver), no una medida.
  bool get isCode => valueMap.isNotEmpty || constantValue != null;

  /// Cómo se nombra el repuesto mientras falta la rueda: «neumático»,
  /// «cassette», «piñón de rosca», «maza», «rotor».
  String get partNoun => switch (templateKey) {
        'tire' => 'neumático',
        'cassette' => 'cassette',
        'freewheel' => 'piñón de rosca',
        'hub' => 'maza',
        'rim' => 'llanta',
        'fork' => 'horquilla',
        'handlebar' => 'manubrio',
        'stem' => 'potencia',
        'seatpost' => 'tija',
        'shifter' => 'mando',
        'brake_lever' => 'manilla',
        'grip' => 'puños',
        _ => componentLabel.split(' ').first,
      };

  /// Un código nombrado sin su rueda: «driver Shimano HG», «anclaje Center
  /// Lock».
  String codeNoun(Object? value) => switch (bikeFactKey) {
        kSteererFitKey => 'tubo ${measureLabel(value)}',
        kSeatpostKindKey => 'tija ${measureLabel(value).toLowerCase()}',
        _ => '${_isRotorMount(bikeFactKey) ? 'anclaje' : 'driver'} '
            '${measureLabel(value)}',
      };

  /// «622 (29″/700c)», «180 mm», «Shimano HG», «Center Lock», «32H».
  String measureLabel(Object? value) {
    if (bikeFactKey == 'freehubType') {
      return kDrivetrainFreehubTypeOptions['$value'] ?? '$value';
    }
    if (_isRotorMount(bikeFactKey)) return rotorMountLabel(value);
    if (bikeFactKey == kSteererFitKey) {
      return kSteererFitLabels['$value'] ?? '$value';
    }
    if (bikeFactKey == kSeatpostKindKey) {
      return kSeatpostKindLabels['$value'] ?? '$value';
    }
    if (_isSpokeHoles(bikeFactKey)) return '${value}H';
    final measured = valueDecimals > 0 ? _measure(value) : null;
    if (measured != null) return cockpitMillimeters(measured);
    final whole = _wholeMeasure(value);
    if (whole != null && _isWheelBsd(bikeFactKey)) {
      return isoWheelBsdLabel(whole);
    }
    return unit == null ? '$value' : '$value $unit';
  }

  /// Lo que la ficha técnica del producto dice en la ficha de la bici por
  /// esta fila (`bike_fact_link_value_internal`): el código de la familia, el
  /// de su mapa o una medida entera en su rango. Nulo si no lo dice, si no
  /// tiene código en la ficha de la bici o si el producto no cumple la
  /// condición de la fila.
  Object? productValue(Map<String, dynamic> specValues) =>
      productMeetsCondition(specValues) ? rawProductValue(specValues) : null;

  /// Lo mismo sin la condición de la fila: lo que dice una maza de un juego
  /// sobre su rueda (`job_hub_at_wheel_internal`).
  Object? rawProductValue(Map<String, dynamic> specValues) {
    if (constantValue != null) return constantValue;
    final raw = specValues[specKey];
    if (valueMap.isNotEmpty) return raw is String ? valueMap[raw] : null;
    if (valueDecimals > 0) {
      // Hasta los decimales de la fila, sin redondear: 31.85 no es 31,8
      // (`bike_fact_link_value_internal`).
      final measured = _measure(raw);
      if (measured == null || !accepts(measured)) return null;
      final scale = valueDecimals == 1 ? 10 : 100;
      final scaled = measured * scale;
      if ((scaled - scaled.roundToDouble()).abs() > 1e-9) return null;
      return measured == measured.truncateToDouble()
          ? measured.toInt()
          : measured;
    }
    final whole = _wholeMeasure(raw);
    return whole != null && accepts(whole) ? whole : null;
  }

  /// La pieza con [value] calza con lo que la bici dice ([current]) sin ser
  /// lo mismo.
  bool fitsWith(Object? value, Object? current) =>
      fits['$value']?.contains('$current') ?? false;

  /// Lo que la bici tiene que tener para que la pieza calce: si la ficha lo
  /// confirma con otro valor, la pieza no calza.
  final String? requiresFactKey;
  final Set<String> requiresFactValues;

  /// El rango de taller de la clave (el mismo del parche): una medida fuera
  /// de él es un error de la ficha técnica y no se propone.
  final num? minValue;
  final num? maxValue;

  bool accepts(num value) =>
      (minValue == null || value >= minValue!) &&
      (maxValue == null || value <= maxValue!);

  static BikeFactSpecLink? fromJson(Map<String, dynamic> json) {
    final position = switch (json['position']) {
      'front' => BikeMemoryLocation.front,
      'rear' => BikeMemoryLocation.rear,
      // Toda la bici: horquilla, manubrio, tija (20261002170000).
      'none' => BikeMemoryLocation.none,
      _ => null,
    };
    final specKey = json['spec_key'];
    final bikeFactKey = json['bike_fact_key'];
    final componentLabel = json['component_label'];
    if (position == null ||
        specKey is! String ||
        bikeFactKey is! String ||
        componentLabel is! String) {
      return null;
    }
    final requiresValues = json['requires_fact_values'];
    final article = json['component_article'];
    final templateKey = json['template_key'];
    final valueMap = json['value_map'];
    final fits = json['fits'];
    final condition = json['product_condition'];
    final isCode = valueMap is Map || json['constant_value'] is String;
    return BikeFactSpecLink(
      specKey: specKey,
      position: position,
      bikeFactKey: bikeFactKey,
      componentLabel: componentLabel,
      componentArticle:
          article is String && article.isNotEmpty ? article : 'el',
      templateKey: templateKey is String && templateKey.isNotEmpty
          ? templateKey.trim().toLowerCase()
          : null,
      mustFit: json['on_mismatch'] == 'conflict',
      isCheck: json['on_mismatch'] == 'check',
      unit: json['unit'] as String?,
      requiresFactKey: json['requires_fact_key'] as String?,
      requiresFactValues: requiresValues is List
          ? requiresValues.whereType<String>().toSet()
          : const {},
      // Un código no tiene rango de taller (su fila guarda 0 y 0).
      minValue: isCode ? null : _number(json['min_value']),
      maxValue: isCode ? null : _number(json['max_value']),
      valueMap: valueMap is Map
          ? {
              for (final entry in valueMap.entries)
                if (entry.value is String)
                  '${entry.key}': entry.value as String,
            }
          : const {},
      constantValue: json['constant_value'] as String?,
      fits: fits is Map
          ? {
              for (final entry in fits.entries)
                if (entry.value is List)
                  '${entry.key}':
                      (entry.value as List).whereType<String>().toSet(),
            }
          : const {},
      productConditionKey:
          condition is Map ? condition['spec_key'] as String? : null,
      productConditionMin: condition is Map ? _number(condition['min']) : null,
      productConditionMax: condition is Map ? _number(condition['max']) : null,
      productConditionValues: condition is Map && condition['values'] is List
          ? (condition['values'] as List).whereType<String>().toSet()
          : null,
      productConditionMissingOk:
          condition is Map && condition['missing_ok'] == true,
      valueDecimals: switch (json['value_decimals']) {
        final int decimals when decimals > 0 && decimals <= 2 => decimals,
        _ => 0,
      },
    );
  }
}

num? _number(Object? value) =>
    value is num ? value : num.tryParse(value?.toString() ?? '');

bool _isWheelBsd(String key) => kWheelBsdFactKeyByPosition.containsValue(key);

bool _isRotorMount(String? key) =>
    key == 'frontRotorMount' || key == 'rearRotorMount';

bool _isSpokeHoles(String? key) =>
    key == 'frontSpokeHoles' || key == 'rearSpokeHoles';

String _wheelWord(String? key) =>
    key != null && key.startsWith('front') ? 'delantera' : 'trasera';

String _rotorWord(String? key) =>
    key != null && key.startsWith('front') ? 'delantero' : 'trasero';

/// De qué bici es una línea, como lo decide `job_line_bike_internal`: la de
/// su pestaña, y nada más. General es lo que el cliente compra aparte, así
/// que una línea de General no es de ninguna bici, tampoco en un trabajo de
/// una sola (dueño, 2026-10-01; 20261001195000); un trabajo sin bicis no
/// tiene ficha que cambiar.
enum PartLineBike { resolved, general, none }

/// La bici de una línea según dónde está: en la pestaña de una bici
/// ([inBikeTab]) o en General, con las [bikeCount] bicis del trabajo.
PartLineBike partLineBike({
  required bool inBikeTab,
  required int bikeCount,
}) {
  if (inBikeTab) return PartLineBike.resolved;
  return bikeCount > 0 ? PartLineBike.general : PartLineBike.none;
}

/// Qué hace el repuesto con la ficha de la bici.
enum PartBikeFactChangeStatus {
  /// La línea no es de ninguna bici: está en General (o el trabajo no tiene
  /// bicis). Al terminar el servidor no escribe y avisa `line_without_bike`;
  /// el chip no promete nada ni guarda marca hasta que la línea se asigne a
  /// su bici («Asignar a…» en su menú, que la pasa sin duplicarla)
  /// (revisión, 2026-09-28; con una sola bici también, 2026-10-01).
  chooseBike,

  /// Falta elegir la rueda: sin ella no cambia nada.
  chooseWheel,

  /// Tiene rueda, pero el mecánico no confirmó el cambio en esta línea: una
  /// línea antigua con rueda, un repuesto reemplazado o una ficha técnica que
  /// cambió. No cambia la ficha hasta que la confirme (tocar el chip o elegir
  /// la rueda). Así un guardado cualquiera de un trabajo viejo no reescribe
  /// la ficha de su bici con un dato de hace meses.
  unconfirmed,

  /// Cambia la ficha al terminar el trabajo (o la llena, si no lo sabía). Lo
  /// que dice la ficha técnica del repuesto entra sin confirmar, salvo que
  /// esté verificada (20260928110000).
  change,

  /// La ficha ya lo dice: no cambia (sólo una ficha técnica verificada lo
  /// confirma).
  confirms,

  /// Calza con lo que la ficha dice sin ser lo mismo (un cassette HG en un
  /// núcleo HG Road 11): la ficha no cambia (20260928120000).
  fits,

  /// No calza con la ficha, pero el mismo trabajo cambia la pieza que lo
  /// decide (la maza trasera, el mando trasero): no se escribe ni se rechaza;
  /// el mecánico lo decide en la ficha (20260928120000).
  pending,

  /// La pieza no calza con la bici: la ficha confirma algo que la pieza no
  /// admite (un rotor en una bici con freno de llanta), la rueda ya es otra
  /// medida (un neumático de 584 en una rueda de 622, o en una bici aro 29"),
  /// el driver es otro (un piñón de rosca en un núcleo HG), la transmisión
  /// tiene otros piñones, la maza no se raya en la rueda que queda, el rotor
  /// no entra en el anclaje de su maza, o la llanta no calza con su
  /// neumático, su maza o su Enrayado. Lo que dice el mismo trabajo (la maza,
  /// el Enrayado, la llanta o el neumático de esa rueda) manda sobre la
  /// ficha. Al terminar no se escribe y queda el aviso.
  incompatible,

  /// Una maza que no cambia la ficha pero no calza con la rueda que queda
  /// (una de 32 perforaciones en una rueda de 36), o cuyo ancho no es el del
  /// cuadro: el servidor no la revisa (no tiene marca), y la línea lo dice
  /// igual (20260928130000).
  caution,
}

/// Por qué queda pendiente: qué pieza del mismo trabajo lo decide.
enum PartBikeFactPending { hubChange, shifterChange }

/// El cambio que una línea de repuesto propone a la ficha de su bici.
class PartBikeFactChange {
  const PartBikeFactChange({
    required this.status,
    required this.value,
    required this.componentLabel,
    this.unit,
    this.link,
    this.current,
    this.currentConfirmed = false,
    this.blockingKey,
    this.blockingValue,
    this.jobFinished = false,
    this.measureOverride,
    this.fitsWheel = false,
    this.pending,
    this.onlyPosition,
    this.spacerNote,
    this.lineBike = PartLineBike.resolved,
    this.blockingSource,
    this.notes = const [],
  });

  final PartBikeFactChangeStatus status;

  /// De qué bici es la línea; sin una, [chooseBike].
  final PartLineBike lineBike;

  /// Lo que dice la ficha técnica del producto en la ficha de la bici: una
  /// medida (180) o un código (`shimano_hg`).
  final Object value;

  /// «rotor trasero», o «rotor» mientras falta la rueda.
  final String componentLabel;
  final String? unit;

  /// La relación de la rueda elegida; nula mientras falta la rueda.
  final BikeFactSpecLink? link;

  /// Lo que dice hoy la ficha de la bici en esa clave, y si está confirmado.
  final Object? current;
  final bool currentConfirmed;

  /// Lo de la bici con lo que la pieza no calza: la clave (`brakeType`,
  /// `frontWheelBsdMm`, [kBikeWheelSizeFactKey], `freehubType`,
  /// `drivetrainConfig`) y su valor (`rim`, `584`, `29"`, `shimano_hg`,
  /// `3x8`).
  final String? blockingKey;
  final String? blockingValue;

  /// El trabajo ya está terminado: el cambio se aplica al guardar la línea.
  final bool jobFinished;

  /// La medida como se dice mientras falta la rueda («622 (29″/700c)»).
  final String? measureOverride;

  /// La pieza calza con la bici y la ficha la anota (un neumático, un
  /// cassette); si no, la cambia (un rotor).
  final bool fitsWheel;

  /// Qué pieza del trabajo decide lo pendiente.
  final PartBikeFactPending? pending;

  /// La única rueda en que va la pieza (un cassette, atrás): mientras falta,
  /// tocar el chip la elige.
  final BikeMemoryLocation? onlyPosition;

  /// Lo que el código de la ficha no dice del calce: `shimano_hg` es la
  /// familia del núcleo, no su largo, y un cassette de 7 piñones lleva un
  /// separador de 4,5 mm en uno de 8 a 10 (revisión de Codex, 2026-09-28).
  final String? spacerNote;

  /// De dónde sale lo que bloquea, si no es la ficha: `job_hub` (la maza que
  /// instala el mismo trabajo en esa rueda), `job_build` (el Enrayado),
  /// `job_rim` (la llanta nueva) o `job_tire` (el neumático nuevo), como
  /// `requires_source` del servidor.
  final String? blockingSource;

  /// Lo que acompaña al cambio sin cambiar su estado: el adaptador de un
  /// rotor de 6 pernos en una maza Center Lock; el ancho de una maza que no es
  /// el del cuadro.
  final List<String> notes;

  /// La marca de este dato (`{key, value}`): lo que el mecánico vio al elegir
  /// la rueda. Una línea guarda las de todos sus datos
  /// ([partChangeMarkerJson]); el servidor aplica cada una al terminar sólo
  /// si todavía calza con el repuesto, la rueda y la bici. Lo que sólo se
  /// revisa no tiene marca.
  Map<String, dynamic>? get marker => link == null || link!.isCheck
      ? null
      : <String, dynamic>{'key': link!.bikeFactKey, 'value': value};

  String get _measure =>
      link?.measureLabel(value) ??
      measureOverride ??
      (unit == null ? '$value' : '$value $unit');
  String get _current {
    final whole = _wholeMeasure(current);
    if ((link?.isCode ?? false) || (link?.valueDecimals ?? 0) > 0) {
      return link!.measureLabel(current);
    }
    if (whole != null && _isSpokeHoles(link?.bikeFactKey)) return '${whole}H';
    return whole != null && link != null && _isWheelBsd(link!.bikeFactKey)
        ? '$whole'
        : '$current';
  }

  String get _when => jobFinished ? 'al guardar' : 'al terminar';

  bool get _fits => fitsWheel;

  String get _wheelChoice => switch (onlyPosition) {
        BikeMemoryLocation.rear => 'toca para elegir la rueda trasera y',
        BikeMemoryLocation.front => 'toca para elegir la rueda delantera y',
        _ => 'elige la rueda para',
      };

  /// Lo que se lee en la línea.
  String get label => switch (status) {
        PartBikeFactChangeStatus.chooseBike => lineBike == PartLineBike.none
            ? '${_capitalized(componentLabel)} $_measure: el trabajo no '
                'tiene bici; la ficha no cambiará'
            : '${_capitalized(componentLabel)} $_measure: asígnalo a su '
                'bici para '
                '${_fits ? 'anotarlo en' : 'cambiar'} la ficha',
        PartBikeFactChangeStatus.chooseWheel => onlyPosition == null
            ? '${_capitalized(componentLabel)} $_measure: elige la rueda para '
                '${_fits ? 'anotarlo en' : 'cambiar'} la ficha'
            : '${_capitalized(componentLabel)} ($_measure): $_wheelChoice '
                '${_fits ? 'anotarlo en' : 'cambiar'} la ficha',
        PartBikeFactChangeStatus.unconfirmed =>
          '${_capitalized(componentLabel)} $_measure: toca para que '
              '${_fits ? 'la ficha lo anote' : 'cambie la ficha'}',
        PartBikeFactChangeStatus.change when current == null => _fits
            ? 'La ficha lo anota $_when: $componentLabel $_measure'
            : 'Cambia la ficha $_when: $componentLabel $_measure',
        // Lo que calza sólo reemplaza lo que escribió esta misma línea.
        PartBikeFactChangeStatus.change => _fits
            ? 'Corrige la ficha $_when: $componentLabel $_current → $_measure'
            : 'Cambia la ficha $_when: $componentLabel $_current → $_measure',
        PartBikeFactChangeStatus.confirms =>
          'La ficha ya dice $componentLabel $_measure',
        PartBikeFactChangeStatus.fits when blockingSource == 'job_hub' =>
          'Calza con la maza del trabajo: $componentLabel '
              '${link?.measureLabel(blockingValue) ?? blockingValue}',
        PartBikeFactChangeStatus.fits =>
          'Calza con la ficha: $componentLabel $_current',
        PartBikeFactChangeStatus.pending => switch (pending) {
            PartBikeFactPending.hubChange =>
              'Pendiente: el trabajo cambia la maza trasera; elige su driver '
                  'en la ficha',
            _ => 'Pendiente: el trabajo cambia el mando trasero; revisa la '
                'transmisión $blockingValue en la ficha',
          },
        PartBikeFactChangeStatus.incompatible ||
        PartBikeFactChangeStatus.caution =>
          switch (blockingKey) {
            kBikeWheelSizeFactKey =>
              'No calza con el aro $blockingValue de la bici: la ficha no '
                  'anotará la $componentLabel',
            final key? when _isWheelBsd(key) =>
              'No calza: en la ficha la ${link?.componentLabel ?? componentLabel} '
                  'es ${isoWheelBsdLabel(int.tryParse(blockingValue ?? '') ?? 0)}',
            'freehubType' when blockingSource == 'job_hub' =>
              'No calza con la maza del trabajo: su driver es '
                  '«${kDrivetrainFreehubTypeOptions[blockingValue] ?? blockingValue}»',
            'freehubType' => 'No calza: en la ficha el driver trasero es '
                '«${kDrivetrainFreehubTypeOptions[blockingValue] ?? blockingValue}»',
            final key? when _isSpokeHoles(key) => switch (blockingSource) {
                'job_build' => 'No calza: el Enrayado arma la rueda '
                    '${_wheelWord(key)} a $blockingValue rayos',
                'job_rim' => 'No calza: la llanta nueva de la rueda '
                    '${_wheelWord(key)} es de $blockingValue perforaciones',
                _ => 'No calza: en la ficha la rueda ${_wheelWord(key)} '
                    'lleva $blockingValue rayos',
              },
            final key? when _isRotorMount(key) => blockingSource == 'job_hub'
                ? 'No calza con la maza del trabajo: su anclaje es '
                    '«${rotorMountLabel(blockingValue)}»'
                : 'No calza: en la ficha el anclaje del rotor '
                    '${_rotorWord(key)} es «${rotorMountLabel(blockingValue)}»',
            // La llanta (20260928140000).
            final key? when key.endsWith('HubSpokeHoles') =>
              blockingSource == 'job_hub'
                  ? 'No calza con la maza del trabajo: tiene $blockingValue '
                      'perforaciones'
                  : 'No calza con la maza que queda: en la ficha la rueda '
                      '${_wheelWord(key)} lleva $blockingValue rayos',
            final key? when key.endsWith('BuildSpokeHoles') =>
              blockingSource == 'job_rim'
                  ? 'No calza: otra llanta del trabajo en la rueda '
                      '${_wheelWord(key)} tiene $blockingValue perforaciones'
                  : 'No calza: el Enrayado arma la rueda ${_wheelWord(key)} '
                      'a $blockingValue rayos',
            final key? when key.endsWith('TireBsdMm') =>
              blockingSource == 'job_tire'
                  ? 'No calza con el neumático del trabajo: es '
                      '${_bsdText(blockingValue)}'
                  : 'No calza con el neumático que queda: en la ficha la '
                      'rueda ${_wheelWord(key)} es ${_bsdText(blockingValue)}',
            final key? when key.endsWith('RimBsdMm') =>
              link?.templateKey == 'rim'
                  ? 'No calza: otra llanta del trabajo en esa rueda es '
                      '${_bsdText(blockingValue)}'
                  : 'No calza con la llanta del trabajo: es '
                      '${_bsdText(blockingValue)}',
            'hubSpacing' => 'Revisa el ancho: la maza mide $_measure y la '
                'bici $blockingValue mm entre punteras',
            'specialLacing' => 'Revisa el rayado: maza ${value}H en una rueda '
                'de $blockingValue',
            'drivetrainConfig' =>
              'No calza: la transmisión de la ficha es $blockingValue '
                  '(${drivetrainRearCogCount(blockingValue)} piñones atrás)',
            // Dirección y cockpit (20261002170000).
            kControlsBarDiameterKey => 'No calza: en la ficha la zona de '
                'mandos es de ${_millimeters(blockingValue)}',
            kHandlebarClampKey => 'No calza: en la ficha la abrazadera del '
                'manubrio es de ${_millimeters(blockingValue)}',
            _ => 'No calza: en la ficha el freno es '
                '«${bikeRequirementLabel(blockingValue)}»; no cambiará el '
                '$componentLabel',
          },
      };

  /// La precaución que acompaña al cambio, cuando la hay.
  String? get tooltip => switch (status) {
        PartBikeFactChangeStatus.chooseBike
            when lineBike == PartLineBike.general =>
          'General es lo que el cliente compra aparte: una línea de General '
              'no es de ninguna bici y, al terminar, la ficha no cambiaría. '
              '«Asignar a…» en el menú de la línea la pasa a su bici, sin '
              'duplicarla.',
        PartBikeFactChangeStatus.unconfirmed =>
          'Esta línea no cambia la ficha de la bici hasta que confirmes que '
              'la pieza se instaló en esa rueda.',
        PartBikeFactChangeStatus.change
            when current != null &&
                !_fits &&
                link?.bikeFactKey != null &&
                link!.bikeFactKey.endsWith('RotorSizeMm') =>
          [
            'Cambia de diámetro: confirma el adaptador, el cáliper y lo que '
                'admite el cuadro u horquilla. $_declared',
            ...notes,
          ].join(' '),
        PartBikeFactChangeStatus.change =>
          [_declared, if (spacerNote != null) spacerNote!, ...notes].join(' '),
        // El servidor confirma si la ficha técnica del producto está
        // verificada, y la app no lo sabe: se dice la regla, no el caso.
        PartBikeFactChangeStatus.confirms when !currentConfirmed => [
            'Queda sin confirmar, salvo que la ficha técnica del repuesto esté '
                'verificada; la medida o elección del mecánico sí la confirma.',
            if (spacerNote != null) spacerNote!,
            ...notes,
          ].join(' '),
        PartBikeFactChangeStatus.confirms =>
          [if (spacerNote != null) spacerNote!, ...notes].join(' ').isEmpty
              ? null
              : [if (spacerNote != null) spacerNote!, ...notes].join(' '),
        // SRAM (XD en XDR) y Shimano C-731 (HG en HG Road 11): 1,85 mm; un
        // cassette de 7 lleva además el de 4,5 mm.
        PartBikeFactChangeStatus.fits =>
          'La ficha no cambia: entra en ese núcleo con separador (1,85 mm; '
              'uno de 7 piñones lleva además el de 4,5 mm).',
        PartBikeFactChangeStatus.pending => switch (pending) {
            PartBikeFactPending.hubChange =>
              'La ficha dice otro driver, pero la maza nueva lo decide: '
                  'elígelo en la ficha de la bici y guarda el trabajo.',
            _ => 'La transmisión de la ficha tiene otros piñones, pero el '
                'mando nuevo puede cambiarla: si cambió, corrígela en la ficha '
                'de la bici y guarda el trabajo.',
          },
        // Los mismos consejos que `bike_fact_requirement_advice`.
        PartBikeFactChangeStatus.incompatible
            when blockingKey == 'brakeType' || blockingKey == null =>
          'Si la bici lleva freno de disco, corrige el tipo de freno en su '
              'ficha; si no, quita la línea.',
        PartBikeFactChangeStatus.incompatible
            when blockingKey == 'freehubType' && blockingSource == 'job_hub' =>
          'La maza trasera que instala este trabajo dice otro driver: si esa '
              'maza es la que va, cambia esta línea; si no, corrige la de la '
              'maza.',
        PartBikeFactChangeStatus.incompatible
            when blockingKey == 'freehubType' =>
          'Revisa el núcleo de la maza trasera: si es otro, corrige el driver '
              'en la ficha de la bici y guarda el trabajo; si no, cambia la '
              'línea.',
        PartBikeFactChangeStatus.incompatible
            when blockingKey == 'drivetrainConfig' =>
          'Un cassette o piñón de otra velocidad necesita el mando de esa '
              'velocidad: si también lo cambiaste, agrega su línea o corrige '
              'la transmisión en la ficha; si no, cambia la línea.',
        // Los mismos consejos que `bike_fact_requirement_advice`
        // (20260928130000).
        PartBikeFactChangeStatus.incompatible ||
        PartBikeFactChangeStatus.caution when _isSpokeHoles(blockingKey) =>
          [
            'Una maza con menos perforaciones que la llanta no se puede '
                'rayar: si también cambiaste la llanta, agrega su línea en esa '
                'rueda; si la rueda lleva otra cantidad, corrige la ficha; si '
                'no, cambia la línea.',
            ...notes,
          ].join(' '),
        PartBikeFactChangeStatus.incompatible when _isRotorMount(blockingKey) =>
          [
            'Un rotor Center Lock no va en una maza de 6 pernos, y uno de 6 '
                'pernos va en una Center Lock sólo con el adaptador SM-RTAD05, '
                'que no sirve con araña de aluminio (flotantes, SM-RT86 y '
                'SM-RT76): si la maza es otra, corrige la ficha; si no, cambia '
                'la línea.',
            ...notes,
          ].join(' '),
        // Los mismos consejos que `bike_fact_requirement_advice`
        // (20260928140000).
        PartBikeFactChangeStatus.incompatible
            when blockingKey?.endsWith('HubSpokeHoles') ?? false =>
          'Una llanta se raya en una maza con sus mismas perforaciones (o con '
              'más, en los patrones de Sheldon Brown), nunca con menos: si '
              'también cambiaste la maza, agrega su línea en esa rueda; si la '
              'maza tiene otra cantidad, corrige la ficha; si no, cambia la '
              'línea.',
        PartBikeFactChangeStatus.incompatible
            when blockingKey?.endsWith('BuildSpokeHoles') ?? false =>
          'La rueda queda con las perforaciones de su llanta: si el Enrayado '
              'u otra llanta de esa rueda dice otra cantidad, corrige esa '
              'línea; si no, cambia ésta.',
        PartBikeFactChangeStatus.incompatible
            when blockingKey?.endsWith('TireBsdMm') ?? false =>
          'Una llanta y su neumático tienen el mismo BSD: si también '
              'cambiaste el neumático, agrega su línea en esa rueda; si la '
              'rueda es otra, corrige la ficha; si no, cambia la línea.',
        PartBikeFactChangeStatus.incompatible
            when blockingKey?.endsWith('RimBsdMm') ?? false =>
          'Un neumático calza sólo en una llanta de su mismo BSD: si la llanta '
              'del trabajo es la que va, cambia esta línea; si no, corrige la '
              'de la llanta.',
        PartBikeFactChangeStatus.incompatible
            when blockingKey == kBikeWheelSizeFactKey =>
          kWheelSizeAdvice,
        // Los mismos consejos que `bike_fact_requirement_advice`
        // (20261002170000).
        PartBikeFactChangeStatus.incompatible
            when blockingKey == kControlsBarDiameterKey =>
          'Manillas, mandos y puños calzan por la zona de mandos del manubrio '
              '(22,2 mm en uno plano, 23,8 mm en uno de ruta): si también '
              'cambiaste el manubrio, agrega su línea; si la bici tiene otro, '
              'corrige la ficha; si no, cambia la línea.',
        PartBikeFactChangeStatus.incompatible
            when blockingKey == kHandlebarClampKey =>
          'Una potencia aprieta el manubrio por su centro y tiene que ser de '
              'su misma medida (con laina, un manubrio más delgado en una '
              'potencia más grande, nunca al revés): si también cambiaste el '
              'manubrio, agrega su línea; si la bici tiene otra medida, '
              'corrige la ficha; si no, cambia la línea.',
        PartBikeFactChangeStatus.caution when blockingKey == 'specialLacing' =>
          [...notes, 'La ficha no cambia.'].join(' '),
        PartBikeFactChangeStatus.caution =>
          'El ancho entre punteras es del cuadro (u horquilla), no de la '
              'maza: confirma tapas o adaptadores de su fabricante. La ficha '
              'no cambia.',
        PartBikeFactChangeStatus.incompatible =>
          'Revisa la medida del neumático y la de esa rueda: si el neumático '
              'sí va ahí, corrige la ficha de la bici y guarda el trabajo; si '
              'no, cambia la línea.',
        _ => null,
      };

  static const String _declared =
      'Entra como lo dice la ficha técnica del repuesto, sin confirmar, '
      'salvo que esa ficha esté verificada.';
}

/// «23,8 mm», o el texto tal cual si no es una medida.
String _millimeters(String? value) {
  final measured = _measure(value);
  return measured == null ? (value ?? '?') : cockpitMillimeters(measured);
}

String _capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// Qué hacer con una pieza que el aro escrito de la bici no admite
/// (`bike_fact_requirement_advice('bikes.wheel_size')`): vale para un
/// neumático y para una llanta.
const String kWheelSizeAdvice = 'Revisa la medida de la pieza y el aro de la '
    'bici: si la pieza sí va ahí, corrige el aro en la ficha de la bici y '
    'guarda el trabajo; si no, cambia la línea.';

/// «622 (29″/700c)», o el texto tal cual («584 o 622»).
String _bsdText(String? value) {
  final whole = int.tryParse(value ?? '');
  return whole == null ? value ?? '?' : isoWheelBsdLabel(whole);
}

/// Lo que la ficha confirma y con lo que la pieza no calza, con la etiqueta
/// del editor de la ficha («Llanta (rim)»).
String bikeRequirementLabel(String? value) => value == null || value.isEmpty
    ? 'otro sistema'
    : kBikeProfileBrakeTypeOptions[value] ?? value;

/// Una medida entera de la ficha técnica del producto: 180 o «180». Un
/// decimal no se redondea a una medida de la bici (la misma regla que
/// `job_line_part_change_internal`).
int? _wholeMeasure(Object? value) {
  final number = value is num
      ? value
      : value is String && RegExp(r'^\d{1,4}(?:\.0+)?$').hasMatch(value.trim())
          ? num.tryParse(value.trim())
          : null;
  if (number == null ||
      !number.isFinite ||
      number <= 0 ||
      number != number.truncateToDouble()) {
    return null;
  }
  return number.toInt();
}

/// Lo que la ficha dice y cuenta como sabido: «desconocido» no refuta
/// (`bike_fact_part_conflict_internal`).
Object? _knownFact(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim().toLowerCase();
  return text.isEmpty || text == 'unknown' || text == 'desconocido'
      ? null
      : value;
}

/// Dos valores de la ficha son el mismo: medidas por número, códigos por
/// texto (`bike_fact_value_equal`).
bool _sameFact(Object? a, Object? b) {
  if (a == null || b == null) return false;
  if (a is num && b is num) return a == b;
  // Una medida, también con décimas: 22.2 y «22.2» son lo mismo.
  if (a is num || b is num) {
    final measuredA = _measure(a);
    return measuredA != null && measuredA == _measure(b);
  }
  return '$a' == '$b';
}

/// Una medida de la ficha técnica, entera o con décimas: 31.8, «31.8» o
/// «31,8», como la lee `bike_fact_link_value_internal`.
num? _measure(Object? value) {
  final text = value is String ? value.trim().replaceAll(',', '.') : null;
  final number = value is num
      ? value
      : text != null && RegExp(r'^\d{1,4}(?:\.\d+)?$').hasMatch(text)
          ? num.tryParse(text)
          : null;
  if (number == null || !number.isFinite || number <= 0) return null;
  return number;
}

/// Dos marcas dicen lo mismo: la misma clave y la misma medida o el mismo
/// código.
bool samePartChangeMarker(Map<String, dynamic>? a, Map<String, dynamic>? b) {
  if (a == null || b == null) return a == b;
  if (a['key'] != b['key']) return false;
  // Una medida por valor, también con décimas (31.8; 20261002170000).
  final measuredA = _measure(a['value']);
  final measuredB = _measure(b['value']);
  if (measuredA != null || measuredB != null) {
    return measuredA != null && measuredA == measuredB;
  }
  final codeA = a['value'];
  return codeA is String && codeA.isNotEmpty && codeA == b['value'];
}

/// Las marcas de una línea (`service_configuration_data.part_change`): una
/// marca `{key, value}` o, si la pieza instala varios datos (una maza trasera
/// con driver y anclaje), una lista. Siempre como lista ordenada por clave;
/// lo que no es una marca no cuenta (`job_line_part_change_marks_internal`).
List<Map<String, dynamic>> partChangeMarks(Object? raw) {
  final marks = <Map<String, dynamic>>[
    for (final mark in raw is List ? raw : [raw])
      if (mark is Map && mark['key'] is String && mark.containsKey('value'))
        Map<String, dynamic>.from(mark),
  ]..sort((a, b) => '${a['key']}'.compareTo('${b['key']}'));
  return marks;
}

/// Lo que guarda la línea: una marca como objeto (como siempre), varias
/// como lista; ninguna, nada.
Object? partChangeMarkerJson(Iterable<Map<String, dynamic>?> marks) {
  final list = partChangeMarks([
    for (final mark in marks)
      if (mark != null) mark,
  ]);
  return switch (list.length) { 0 => null, 1 => list.single, _ => list };
}

/// La marca de [key] entre las de una línea, si hay una sola: dos marcas de
/// la misma clave no dicen cuál vale (`job_line_part_change_internal`).
Map<String, dynamic>? partChangeMarkFor(Object? raw, String key) {
  final marks = partChangeMarks(raw).where((mark) => mark['key'] == key);
  return marks.length == 1 ? marks.single : null;
}

/// Qué familias instalan atrás las otras líneas del trabajo en la misma bici
/// (`job_installs_rear_family_internal`): una maza trasera (`hub`) decide el
/// driver; un mando trasero (`shifter`), la transmisión. Cada línea con su
/// rueda y la ficha técnica de su producto (con `__template_key`). Trasera
/// con evidencia: la rueda trasera en la línea, o la posición del producto
/// (Trasera, Juego; Derecho (trasero), Par). Una en la rueda delantera, o sin
/// rueda ni posición, no cuenta (revisión de Codex, 2026-09-28).
Set<String> rearFamiliesInstalledByJob(
  Iterable<({BikeMemoryLocation location, Map<String, dynamic>? specs})> lines,
) {
  final families = <String>{};
  for (final line in lines) {
    final specs = line.specs;
    if (specs == null || line.location == BikeMemoryLocation.front) continue;
    final family = specs['__template_key']?.toString().trim().toLowerCase();
    final position = switch (family) {
      'hub' => specs['hub_package_position'],
      'shifter' => specs['shifter_position'],
      _ => null,
    };
    if (family == null || !(family == 'hub' || family == 'shifter')) continue;
    if (line.location == BikeMemoryLocation.rear ||
        _rearPositions.contains(position)) {
      families.add(family);
    }
  }
  return families;
}

const Set<String> _rearPositions = {
  'Trasera',
  'Juego (delantera y trasera)',
  'Derecho (trasero)',
  'Par',
};

/// Otra línea del mismo trabajo y la misma bici, como la mira el cruce: su
/// rueda, la ficha técnica de su producto (con `__template_key`) y, si es un
/// Enrayado, sus perforaciones y la rueda que armó (`hole_count`,
/// `which_wheel`).
typedef JobWheelLine = ({
  BikeMemoryLocation location,
  Map<String, dynamic>? specs,
  int? holeCount,
  BikeMemoryLocation? buildWheel,
});

/// La maza que instala el trabajo en una rueda: su driver, su anclaje y sus
/// perforaciones, si todas las mazas de esa rueda los dicen igual; si dicen
/// dos cantidades, [holesEither] («32 o 36») (`job_hub_at_wheel_internal`).
typedef JobWheelHub = ({
  String? driver,
  String? rotorMount,
  int? holes,
  String? holesEither,
});

/// El BSD que dicen las llantas o los neumáticos que el trabajo instala en
/// una rueda (`job_wheel_bsd_internal`): [value] si todos lo dicen igual,
/// [either] si dicen dos; ninguno si alguno no lo dice (no refuta).
typedef JobWheelBsd = ({int? value, String? either});

/// Los rayos de la rueda que arma el trabajo (`job_wheel_spokes_internal`).
/// Si dos Enrayados o dos llantas dicen otra cantidad, [holes] es nulo y
/// [either] las dice («36 o 40»): el trabajo la decide pero no se sabe cuál,
/// y una maza no se da por buena (revisión de Codex, 2026-09-28). Si una
/// llanta no dice las suyas, ninguna de las dos: no refuta.
typedef JobWheelSpokes = ({int? holes, String? either, String source});

/// Lo que el mismo trabajo instala en cada rueda de la bici: con esto se
/// cruza una pieza con otra (el cassette con el driver de la maza, el rotor
/// con su anclaje, la maza con los rayos de la rueda), y manda sobre la
/// ficha, como en el servidor (20260928130000).
class JobWheelParts {
  const JobWheelParts({
    this.rearFamilies = const {},
    this.hubs = const {},
    this.spokes = const {},
    this.rimBsd = const {},
    this.tireBsd = const {},
  });

  /// [rearFamiliesInstalledByJob].
  final Set<String> rearFamilies;
  final Map<BikeMemoryLocation, JobWheelHub> hubs;
  final Map<BikeMemoryLocation, JobWheelSpokes> spokes;

  /// Las llantas y los neumáticos del trabajo en cada rueda (con su rueda
  /// elegida): el neumático y la llanta se miden entre sí (20260928140000).
  final Map<BikeMemoryLocation, JobWheelBsd> rimBsd;
  final Map<BikeMemoryLocation, JobWheelBsd> tireBsd;
}

/// Lee [JobWheelParts] de las otras líneas del trabajo en la misma bici (sin
/// la línea que se mira): una maza cuenta en la rueda de su línea o, sin
/// rueda, en la de su posición (un juego, en las dos); los rayos los dice el
/// Enrayado de esa rueda, si no la llanta nueva de esa rueda, si no la ficha.
JobWheelParts jobWheelParts(
  Iterable<JobWheelLine> lines,
  List<BikeFactSpecLink> links,
) {
  final hubValues = <BikeMemoryLocation, List<(Object?, Object?, int?)>>{};
  final builds = <BikeMemoryLocation, Set<int>>{};
  final rims = <BikeMemoryLocation, List<int?>>{};
  final rimBsds = <BikeMemoryLocation, List<int?>>{};
  final tireBsds = <BikeMemoryLocation, List<int?>>{};
  BikeFactSpecLink? hubLink(String key) {
    for (final link in links) {
      if (link.templateKey == 'hub' &&
          !link.isCheck &&
          link.bikeFactKey == key) {
        return link;
      }
    }
    return null;
  }

  for (final line in lines) {
    final holes = line.holeCount;
    // Fuera del rango de taller es un error de tipeo, no una rueda.
    if (holes != null && (holes < 12 || holes > 48)) continue;
    if (holes != null) {
      // Como el servidor: la rueda de la línea, y sólo sin ella la que dice
      // el asistente (`coalesce(nullif(location_key, 'none'), which_wheel)`).
      final wheel = switch (line.location) {
        BikeMemoryLocation.front || BikeMemoryLocation.rear => line.location,
        BikeMemoryLocation.none => line.buildWheel,
        _ => null,
      };
      if (wheel == BikeMemoryLocation.front ||
          wheel == BikeMemoryLocation.rear) {
        builds.putIfAbsent(wheel!, () => {}).add(holes);
      }
      continue;
    }
    final specs = line.specs;
    final family = specs?['__template_key']?.toString().trim().toLowerCase();
    if (specs == null) continue;
    if (family == 'rim' &&
        (line.location == BikeMemoryLocation.front ||
            line.location == BikeMemoryLocation.rear)) {
      rims
          .putIfAbsent(line.location, () => [])
          .add(_wholeMeasure(specs['spoke_hole_count']));
    }
    // El BSD de las llantas y los neumáticos, en la rueda de su línea.
    if ((family == 'rim' || family == 'tire') &&
        (line.location == BikeMemoryLocation.front ||
            line.location == BikeMemoryLocation.rear)) {
      final bsd = _wholeMeasure(specs['bead_seat_diameter_mm']);
      (family == 'rim' ? rimBsds : tireBsds)
          .putIfAbsent(line.location, () => [])
          .add(bsd != null && bsd >= 150 && bsd <= 700 ? bsd : null);
    }
    if (family != 'hub') continue;
    // Una maza que dice ser de la otra rueda no es evidencia de ésta.
    final position = specs['hub_package_position']?.toString();
    final wheels = switch (line.location) {
      BikeMemoryLocation.front when position != 'Trasera' => const [
          BikeMemoryLocation.front,
        ],
      BikeMemoryLocation.rear when position != 'Delantera' => const [
          BikeMemoryLocation.rear,
        ],
      BikeMemoryLocation.front ||
      BikeMemoryLocation.rear =>
        const <BikeMemoryLocation>[],
      _ => switch (specs['hub_package_position']?.toString()) {
          'Delantera' => const [BikeMemoryLocation.front],
          'Trasera' => const [BikeMemoryLocation.rear],
          'Juego (delantera y trasera)' => const [
              BikeMemoryLocation.front,
              BikeMemoryLocation.rear,
            ],
          _ => const <BikeMemoryLocation>[],
        },
    };
    for (final wheel in wheels) {
      final mountKey = wheel == BikeMemoryLocation.front
          ? 'frontRotorMount'
          : 'rearRotorMount';
      final holes = _wholeMeasure(specs['spoke_hole_count']);
      hubValues.putIfAbsent(wheel, () => []).add((
        wheel == BikeMemoryLocation.rear
            ? hubLink('freehubType')?.rawProductValue(specs)
            : null,
        hubLink(mountKey)?.rawProductValue(specs),
        holes != null && holes >= 12 && holes <= 48 ? holes : null,
      ));
    }
  }

  String? agreed(Iterable<Object?> values) {
    final list = values.toList();
    if (list.isEmpty || list.any((value) => value == null)) return null;
    final distinct = list.map((value) => '$value').toSet();
    return distinct.length == 1 ? distinct.single : null;
  }

  return JobWheelParts(
    rearFamilies: rearFamiliesInstalledByJob([
      for (final line in lines)
        if (line.holeCount == null)
          (location: line.location, specs: line.specs),
    ]),
    hubs: {
      for (final entry in hubValues.entries)
        entry.key: (
          driver: entry.key == BikeMemoryLocation.rear
              ? agreed(entry.value.map((hub) => hub.$1))
              : null,
          rotorMount: agreed(entry.value.map((hub) => hub.$2)),
          holes: _agreedMeasure(entry.value.map((hub) => hub.$3)).value,
          holesEither: _agreedMeasure(entry.value.map((hub) => hub.$3)).either,
        ),
    },
    rimBsd: {
      for (final entry in rimBsds.entries)
        entry.key: _agreedMeasure(entry.value),
    },
    tireBsd: {
      for (final entry in tireBsds.entries)
        entry.key: _agreedMeasure(entry.value),
    },
    spokes: {
      for (final wheel in const [
        BikeMemoryLocation.front,
        BikeMemoryLocation.rear,
      ])
        if (builds[wheel] case final counts?)
          wheel: (
            holes: counts.length == 1 ? counts.single : null,
            either: counts.length > 1 ? _either(counts) : null,
            source: 'job_build',
          )
        else if (rims[wheel] case final holes?)
          wheel: (
            // Las que dicen sus perforaciones (`array_agg(distinct …) filter
            // (…)` en el servidor).
            holes: holes.whereType<int>().toSet().length == 1
                ? holes.whereType<int>().first
                : null,
            either: holes.whereType<int>().toSet().length > 1
                ? _either(holes.whereType<int>())
                : null,
            source: 'job_rim',
          ),
    },
  );
}

/// «36 o 40», de menor a mayor, como `string_agg(… order by …)`.
String _either(Iterable<int> counts) =>
    (counts.toSet().toList()..sort()).join(' o ');

/// Una medida que varias piezas dicen: la que dicen las que la dicen, si es
/// una sola; las cantidades, si son más (`count(distinct x) = 1`). Una pieza
/// que no la dice no esconde a la que sí (revisión de Codex, 2026-09-29).
JobWheelBsd _agreedMeasure(Iterable<int?> measures) {
  final stated = measures.whereType<int>().toSet();
  return (
    value: stated.length == 1 ? stated.single : null,
    either: stated.length > 1 ? _either(stated) : null,
  );
}

/// Una maza con más perforaciones que la llanta se raya con los patrones de
/// Sheldon Brown («Spoking patterns for large hubs»); con menos, no
/// (`hub_lacing_fits`).
bool hubLacingFits(int hub, int rim) =>
    hub == rim || _sheldonLacingPairs.contains((hub, rim));

const Set<(int, int)> _sheldonLacingPairs = {
  (40, 24), (32, 24), (48, 36), (36, 24), (48, 32), (40, 32), //
  (36, 28), (48, 24), (28, 24), (32, 28), (36, 32), (40, 36),
};

/// El cambio que propone un repuesto: el primero de [partBikeFactChanges]
/// (un rotor, un neumático, un cassette proponen uno solo).
PartBikeFactChange? partBikeFactChange({
  required List<BikeFactSpecLink> links,
  required Map<String, dynamic> productSpecValues,
  required BikeMemoryLocation location,
  Object? confirmedMarker,
  Object? writtenMarker,
  Map<String, dynamic> bikeValues = const {},
  Map<String, dynamic> bikeConfirmed = const {},
  Map<String, dynamic> bikeSources = const {},
  String? bikeWheelSize,
  Set<String> jobRearFamilies = const {},
  JobWheelParts? job,
  Map<BikeMemoryLocation, double> bikeHubSpacingMm = const {},
  PartLineBike lineBike = PartLineBike.resolved,
  bool jobFinished = false,
}) {
  final changes = partBikeFactChanges(
    links: links,
    productSpecValues: productSpecValues,
    location: location,
    confirmedMarker: confirmedMarker,
    writtenMarker: writtenMarker,
    bikeValues: bikeValues,
    bikeConfirmed: bikeConfirmed,
    bikeSources: bikeSources,
    bikeWheelSize: bikeWheelSize,
    jobRearFamilies: jobRearFamilies,
    job: job,
    bikeHubSpacingMm: bikeHubSpacingMm,
    lineBike: lineBike,
    jobFinished: jobFinished,
  );
  return changes.isEmpty ? null : changes.first;
}

/// La marca de un repuesto de toda la bici (horquilla, manubrio, tija,
/// potencia, manillas, mandos, puños): no tiene rueda que elegir, así que la
/// línea la lleva sola desde que se agrega en la pestaña de su bici (dueño,
/// 2026-10-02: nada que dependa de que alguien toque algo); al terminar el
/// trabajo, el servidor la revisa contra la ficha. Nula si el repuesto no
/// dice nada de toda la bici (20261002170000).
Object? bikeWidePartMarker({
  required List<BikeFactSpecLink> links,
  required Map<String, dynamic> productSpecValues,
}) {
  final templateKey = productSpecValues['__template_key']?.toString();
  final seen = <String>{};
  return partChangeMarkerJson([
    for (final link in links)
      if (link.isBikeWide &&
          !link.isCheck &&
          link.appliesTo(templateKey) &&
          seen.add(link.bikeFactKey))
        if (link.productValue(productSpecValues) case final value?)
          <String, dynamic>{'key': link.bikeFactKey, 'value': value},
  ]);
}

/// En qué ruedas puede ir un repuesto: las de los datos que le escribe a la
/// ficha con su producto. Un cassette o una rueda libre sólo escriben datos
/// de la rueda trasera, así que no tienen lado que elegir; un rotor, una
/// llanta o un neumático, las dos. Vacío si no le escribe nada a la ficha:
/// una cadena no tiene lado (dueño, 2026-10-01: «solo tiene que existir la
/// opción en productos que realmente tengan opciones»).
Set<BikeMemoryLocation> partWheelPositions({
  required List<BikeFactSpecLink> links,
  required Map<String, dynamic> productSpecValues,
}) {
  final templateKey = productSpecValues['__template_key']?.toString();
  return {
    for (final link in links)
      if (!link.isCheck &&
          link.appliesTo(templateKey) &&
          link.productValue(productSpecValues) != null &&
          (link.position == BikeMemoryLocation.front ||
              link.position == BikeMemoryLocation.rear))
        link.position,
  };
}

/// Los cambios que propone un repuesto, uno por dato de la ficha: el rotor,
/// el neumático y el cassette, uno; una maza trasera, su driver y el anclaje
/// del rotor de su rueda. Con la ficha técnica de su producto
/// ([productSpecValues], como la entrega `get_product_spec_contexts_v1`, con
/// su familia en `__template_key`), la rueda de la línea, las marcas que ya
/// confirmó el mecánico ([confirmedMarker]), lo que el servidor dice que
/// esta línea escribió y la ficha todavía dice como suyo ([writtenMarker],
/// de `job_part_change_writers_v1`), la bici (su ficha, el aro escrito
/// [bikeWheelSize] y el ancho entre punteras [bikeHubSpacingMm]) y lo que el
/// mismo trabajo instala en ella ([job]; o sólo [jobRearFamilies]). Vacío si
/// el repuesto no tiene un concepto de la relación con un valor para la
/// ficha, ni una maza que revisar.
List<PartBikeFactChange> partBikeFactChanges({
  required List<BikeFactSpecLink> links,
  required Map<String, dynamic> productSpecValues,
  required BikeMemoryLocation location,
  Object? confirmedMarker,
  Object? writtenMarker,
  Map<String, dynamic> bikeValues = const {},
  Map<String, dynamic> bikeConfirmed = const {},
  Map<String, dynamic> bikeSources = const {},
  String? bikeWheelSize,
  Set<String> jobRearFamilies = const {},
  JobWheelParts? job,
  Map<BikeMemoryLocation, double> bikeHubSpacingMm = const {},
  PartLineBike lineBike = PartLineBike.resolved,
  bool jobFinished = false,
}) {
  final context = job ?? JobWheelParts(rearFamilies: jobRearFamilies);
  final rearFamilies = {...context.rearFamilies, ...jobRearFamilies};
  final templateKey = productSpecValues['__template_key']?.toString();
  final valued = [
    for (final link in links)
      if (!link.isCheck &&
          link.appliesTo(templateKey) &&
          link.productValue(productSpecValues) != null)
        link,
  ];
  if (valued.isEmpty) {
    // Una maza que no cambia la ficha igual se mira contra la rueda que
    // queda: el servidor no la revisa (no tiene marca).
    final caution = lineBike == PartLineBike.resolved
        ? _hubCaution(
            links: links,
            productSpecValues: productSpecValues,
            location: location,
            bikeValues: bikeValues,
            job: context,
            bikeHubSpacingMm: bikeHubSpacingMm,
            jobFinished: jobFinished,
          )
        : null;
    return caution == null ? const [] : [caution];
  }

  // Sin bici no hay ficha: ni se promete ni se confirma (sin relación, sin
  // marca), antes que la rueda.
  if (lineBike != PartLineBike.resolved) {
    final first = valued.first;
    final value = first.productValue(productSpecValues)!;
    return [
      PartBikeFactChange(
        status: PartBikeFactChangeStatus.chooseBike,
        value: value,
        componentLabel: first.partNoun,
        unit:
            _isWheelBsd(first.bikeFactKey) || first.isCode ? null : first.unit,
        measureOverride: first.isCode
            ? '(${first.codeNoun(value)})'
            : first.measureLabel(value),
        fitsWheel: first.mustFit,
        jobFinished: jobFinished,
        lineBike: lineBike,
      ),
    ];
  }

  final atWheel = valued.where((link) => link.position == location).toList();
  if (atWheel.isEmpty) {
    // Sin rueda (o una que la relación no tiene): se pide elegirla. La pieza
    // se nombra sin la posición («rotor trasero» → «rotor»). Si va en una
    // sola rueda (un cassette, una maza trasera), tocar el chip la elige.
    final first = valued.first;
    final value = first.productValue(productSpecValues)!;
    final positions = {for (final link in valued) link.position};
    return [
      PartBikeFactChange(
        status: PartBikeFactChangeStatus.chooseWheel,
        value: value,
        componentLabel: first.partNoun,
        unit:
            _isWheelBsd(first.bikeFactKey) || first.isCode ? null : first.unit,
        measureOverride:
            first.isCode ? first.codeNoun(value) : first.measureLabel(value),
        fitsWheel: first.mustFit,
        jobFinished: jobFinished,
        onlyPosition: positions.length == 1 ? positions.single : null,
      ),
    ];
  }

  // Un dato por clave, en el orden de la marca (por clave).
  final seen = <String>{};
  final perKey = [
    for (final link in atWheel)
      if (seen.add(link.bikeFactKey)) link,
  ]..sort((a, b) => a.bikeFactKey.compareTo(b.bikeFactKey));
  final frameNote = _hubFrameNote(
    productSpecValues: productSpecValues,
    templateKey: templateKey,
    location: location,
    bikeHubSpacingMm: bikeHubSpacingMm,
  );
  // Una llanta es una pieza: si no calza en su rueda, ninguno de sus datos
  // cambia la ficha (`bike_fact_rim_checks_internal`).
  final rimFit = templateKey?.trim().toLowerCase() == 'rim'
      ? _rimFit(
          links: links,
          productSpecValues: productSpecValues,
          position: location,
          job: context,
          bikeValues: bikeValues,
          bikeSources: bikeSources,
          writtenMarker: writtenMarker,
          bikeWheelSize: bikeWheelSize,
        )
      : null;
  return [
    for (final link in perKey)
      _partBikeFactChangeAt(
        link: link,
        links: links,
        productSpecValues: productSpecValues,
        templateKey: templateKey,
        confirmedMarker: partChangeMarkFor(confirmedMarker, link.bikeFactKey),
        writtenMarker: partChangeMarkFor(writtenMarker, link.bikeFactKey),
        bikeValues: bikeValues,
        bikeConfirmed: bikeConfirmed,
        bikeSources: bikeSources,
        bikeWheelSize: bikeWheelSize,
        rearFamilies: rearFamilies,
        job: context,
        jobFinished: jobFinished,
        notes: [
          if (frameNote != null) frameNote,
          if (rimFit?.note case final note?) note,
        ],
        misfit: rimFit?.key == null ? null : rimFit,
      ),
  ];
}

/// Lo que una llanta tiene que calzar en su rueda: el mismo orden que
/// `bike_fact_rim_checks_internal`. Su BSD con otra llanta del trabajo en
/// esa rueda y con el neumático de esa rueda (el del trabajo; si no, el que
/// queda según la ficha), y con el aro escrito salvo que la ficha sepa un BSD
/// que ese aro no admite; sus perforaciones con la rueda que arma el trabajo
/// (el Enrayado u otra llanta: la misma cuenta) y con la maza en que se raya
/// (la del trabajo; si no, la que queda según la ficha). Lo que escribió esta
/// misma línea no es lo que queda: se está corrigiendo. [key] nulo si calza;
/// [note], un patrón de rayado especial que la maza tiene que admitir.
({String? key, String? value, String? source, String? note}) _rimFit({
  required List<BikeFactSpecLink> links,
  required Map<String, dynamic> productSpecValues,
  required BikeMemoryLocation position,
  required JobWheelParts job,
  required Map<String, dynamic> bikeValues,
  required Map<String, dynamic> bikeSources,
  required Object? writtenMarker,
  required String? bikeWheelSize,
}) {
  final side = position == BikeMemoryLocation.front ? 'front' : 'rear';
  int? measure(String specKey) {
    for (final link in links) {
      if (link.templateKey == 'rim' &&
          !link.isCheck &&
          link.position == position &&
          link.specKey == specKey) {
        final value = link.rawProductValue(productSpecValues);
        return value is int ? value : null;
      }
    }
    return null;
  }

  int? remaining(String key) {
    final known = _knownFact(bikeValues[key]);
    if (known == null) return null;
    final own = bikeSources[key] == 'job_completion' &&
        samePartChangeMarker(
          partChangeMarkFor(writtenMarker, key),
          {'key': key, 'value': known},
        );
    return own ? null : _wholeMeasure(known);
  }

  ({String? key, String? value, String? source, String? note}) misfit(
    String key,
    Object? value, [
    String? source,
  ]) =>
      (key: key, value: '$value', source: source, note: null);

  final bsd = measure('bead_seat_diameter_mm');
  if (bsd != null) {
    final rims = job.rimBsd[position];
    if (rims != null &&
        (rims.either != null || (rims.value != null && rims.value != bsd))) {
      return misfit('${side}RimBsdMm', rims.value ?? rims.either, 'job_rim');
    }
    final before = remaining('${side}WheelBsdMm');
    final tire = job.tireBsd[position];
    if (tire != null) {
      if (tire.either != null || (tire.value != null && tire.value != bsd)) {
        return misfit(
            '${side}TireBsdMm', tire.value ?? tire.either, 'job_tire');
      }
    } else if (before != null && before != bsd) {
      return misfit('${side}TireBsdMm', before);
    }
    // El aro escrito refuta, salvo que la ficha sepa un BSD que ese aro no
    // admite: entonces es el aro el que quedó viejo (revisión de Codex,
    // 2026-09-29); con el mismo BSD tampoco.
    final candidates = isoBsdCandidatesForBikeWheelSize(bikeWheelSize);
    if (candidates.isNotEmpty &&
        !candidates.contains(bsd) &&
        (before == null || candidates.contains(before))) {
      return misfit(kBikeWheelSizeFactKey, bikeWheelSize!.trim());
    }
  }

  String? note;
  final holes = measure('spoke_hole_count');
  if (holes != null) {
    final build = job.spokes[position];
    if (build != null &&
        (build.holes != null || build.either != null) &&
        build.holes != holes) {
      return misfit(
          '${side}BuildSpokeHoles', build.holes ?? build.either, build.source);
    }
    final hub = job.hubs[position];
    if (hub != null) {
      if (hub.holesEither != null) {
        return misfit('${side}HubSpokeHoles', hub.holesEither, 'job_hub');
      }
      if (hub.holes case final hubHoles?) {
        if (!hubLacingFits(hubHoles, holes)) {
          return misfit('${side}HubSpokeHoles', hubHoles, 'job_hub');
        }
        if (hubHoles != holes) note = _specialLacingNote(hubHoles, holes);
      }
    } else if (remaining('${side}SpokeHoles') case final before?
        when before >= 12 && before <= 48) {
      if (!hubLacingFits(before, holes)) {
        return misfit('${side}HubSpokeHoles', before);
      }
      if (before != holes) note = _specialLacingNote(before, holes);
    }
  }
  return (key: null, value: null, source: null, note: note);
}

/// Lo que dice el mismo trabajo, si no la ficha: los rayos de esa rueda.
/// [holes] nulo con [either]: el trabajo dice dos cantidades.
({int? holes, String? either, String? source})? _wheelSpokes(
  JobWheelParts job,
  BikeMemoryLocation wheel,
  Map<String, dynamic> bikeValues,
) {
  final decided = job.spokes[wheel];
  if (decided != null) {
    if (decided.holes == null && decided.either == null) return null;
    return (
      holes: decided.holes,
      either: decided.either,
      source: decided.source,
    );
  }
  final key =
      wheel == BikeMemoryLocation.front ? 'frontSpokeHoles' : 'rearSpokeHoles';
  final holes = _wholeMeasure(bikeValues[key]);
  return holes == null ? null : (holes: holes, either: null, source: null);
}

/// El ancho de una maza que no es el del cuadro: la maza no lo cambia; se
/// dice como condición de armado, igual que la matriz (20260928130000).
String? _hubFrameNote({
  required Map<String, dynamic> productSpecValues,
  required String? templateKey,
  required BikeMemoryLocation location,
  required Map<BikeMemoryLocation, double> bikeHubSpacingMm,
}) {
  if (templateKey?.trim().toLowerCase() != 'hub') return null;
  final hubOld = _wholeMeasure(productSpecValues['hub_old_mm']);
  final bikeOld = bikeHubSpacingMm[location];
  if (hubOld == null || bikeOld == null || hubOld == bikeOld) return null;
  return 'La maza mide $hubOld mm entre tuercas y la bici '
      '${_formatMm(bikeOld)} mm entre punteras: el ancho es del cuadro (u '
      'horquilla); confirma tapas o adaptadores de su fabricante.';
}

/// Una maza con más perforaciones que la llanta se raya saltando agujeros de
/// la maza: Sheldon Brown lo documenta para mazas grandes con pestañas
/// firmes, y advierte del torque en la trasera. No se da por hecho.
String _specialLacingNote(int hub, int rim) =>
    'Maza de ${hub}H en una rueda de $rim: se raya con un patrón especial '
    '(Sheldon Brown), que la maza y el armado tienen que admitir; confírmalo '
    'antes de armar.';

String _formatMm(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString().replaceAll('.', ',');

/// Una maza sin datos que escribir (sólo perforaciones, o nada), en su rueda:
/// no se raya en la rueda que queda, o su ancho no es el del cuadro.
PartBikeFactChange? _hubCaution({
  required List<BikeFactSpecLink> links,
  required Map<String, dynamic> productSpecValues,
  required BikeMemoryLocation location,
  required Map<String, dynamic> bikeValues,
  required JobWheelParts job,
  required Map<BikeMemoryLocation, double> bikeHubSpacingMm,
  required bool jobFinished,
}) {
  if (productSpecValues['__template_key']?.toString().trim().toLowerCase() !=
      'hub') {
    return null;
  }
  final wheel = switch (location) {
    BikeMemoryLocation.front || BikeMemoryLocation.rear => location,
    _ => switch (productSpecValues['hub_package_position']?.toString()) {
        'Delantera' => BikeMemoryLocation.front,
        'Trasera' => BikeMemoryLocation.rear,
        _ => null,
      },
  };
  if (wheel == null) return null;
  for (final check in links) {
    if (!check.isCheck ||
        check.position != wheel ||
        !check.appliesTo('hub') ||
        !_isSpokeHoles(check.bikeFactKey) ||
        !check.productMeetsCondition(productSpecValues)) {
      continue;
    }
    final measured = _wholeMeasure(productSpecValues[check.specKey]);
    if (measured == null || !check.accepts(measured)) continue;
    final reference = _wheelSpokes(job, wheel, bikeValues);
    if (reference == null || reference.holes == measured) continue;
    final holes = reference.holes;
    if (holes == null) {
      // El trabajo arma esa rueda con dos cantidades.
      return PartBikeFactChange(
        status: PartBikeFactChangeStatus.caution,
        value: measured,
        componentLabel: 'maza',
        link: check,
        blockingKey: check.bikeFactKey,
        blockingValue: reference.either,
        blockingSource: reference.source,
        jobFinished: jobFinished,
        measureOverride: '${measured}H',
      );
    }
    if (hubLacingFits(measured, holes)) {
      // Se puede rayar, con un patrón que la maza tiene que admitir.
      return PartBikeFactChange(
        status: PartBikeFactChangeStatus.caution,
        value: measured,
        componentLabel: 'maza',
        link: check,
        blockingKey: 'specialLacing',
        blockingValue: '$holes',
        blockingSource: reference.source,
        jobFinished: jobFinished,
        measureOverride: '${measured}H',
        notes: [_specialLacingNote(measured, holes)],
      );
    }
    return PartBikeFactChange(
      status: PartBikeFactChangeStatus.caution,
      value: measured,
      componentLabel: 'maza',
      link: check,
      blockingKey: check.bikeFactKey,
      blockingValue: '$holes',
      blockingSource: reference.source,
      jobFinished: jobFinished,
      measureOverride: '${measured}H',
    );
  }
  final hubOld = _wholeMeasure(productSpecValues['hub_old_mm']);
  final bikeOld = bikeHubSpacingMm[wheel];
  if (hubOld != null && bikeOld != null && hubOld != bikeOld) {
    return PartBikeFactChange(
      status: PartBikeFactChangeStatus.caution,
      value: hubOld,
      componentLabel: 'maza',
      blockingKey: 'hubSpacing',
      blockingValue: _formatMm(bikeOld),
      jobFinished: jobFinished,
      measureOverride: '$hubOld mm',
    );
  }
  return null;
}

/// El cambio de un dato de la ficha en la rueda elegida.
PartBikeFactChange _partBikeFactChangeAt({
  required BikeFactSpecLink link,
  required List<BikeFactSpecLink> links,
  required Map<String, dynamic> productSpecValues,
  required String? templateKey,
  required Map<String, dynamic>? confirmedMarker,
  required Map<String, dynamic>? writtenMarker,
  required Map<String, dynamic> bikeValues,
  required Map<String, dynamic> bikeConfirmed,
  required Map<String, dynamic> bikeSources,
  required String? bikeWheelSize,
  required Set<String> rearFamilies,
  required JobWheelParts job,
  required bool jobFinished,
  List<String> notes = const [],
  ({String? key, String? value, String? source, String? note})? misfit,
}) {
  final value = link.productValue(productSpecValues)!;
  final current = bikeValues[link.bikeFactKey];
  final extraNotes = [...notes];
  PartBikeFactChange withStatus(
    PartBikeFactChangeStatus status, {
    String? blockingKey,
    String? blockingValue,
    String? blockingSource,
    PartBikeFactPending? pending,
  }) =>
      PartBikeFactChange(
        status: status,
        value: value,
        componentLabel: link.componentLabel,
        unit: link.unit,
        link: link,
        current: current,
        currentConfirmed: bikeConfirmed[link.bikeFactKey] == true,
        blockingKey: blockingKey,
        blockingValue: blockingValue,
        blockingSource: blockingSource,
        jobFinished: jobFinished,
        fitsWheel: link.mustFit,
        pending: pending,
        spacerNote: value == 'shimano_hg' &&
                templateKey == 'cassette' &&
                _wholeMeasure(productSpecValues['sprocket_count']) == 7
            ? 'Un cassette de 7 piñones lleva un separador de 4,5 mm en un '
                'núcleo HG de 8 a 10.'
            : null,
        notes: extraNotes,
      );

  // Lo que no calza se dice primero, con marca o sin ella: invitar a
  // confirmar un cambio que el servidor no aplicará confunde (revisión de
  // Codex, 2026-09-28). Una llanta que no calza en su rueda, en cada dato.
  if (misfit?.key case final key?) {
    return withStatus(
      PartBikeFactChangeStatus.incompatible,
      blockingKey: key,
      blockingValue: misfit!.value,
      blockingSource: misfit.source,
    );
  }
  final requiresKey = link.requiresFactKey;
  if (requiresKey != null && bikeConfirmed[requiresKey] == true) {
    final required = bikeValues[requiresKey]?.toString();
    if (required != null && !link.requiresFactValues.contains(required)) {
      return withStatus(
        PartBikeFactChangeStatus.incompatible,
        blockingKey: requiresKey,
        blockingValue: required,
      );
    }
  }

  // Lo que tiene que calzar con la bici (`bike_fact_part_conflict_internal`).
  // El driver lo decide la maza trasera que instala el mismo trabajo, si lo
  // dice: se compara con ella, no con la ficha vieja (20260928130000). Si
  // no, lo que dice la ficha en esa clave, salvo que lo haya escrito esta
  // misma línea y siga siendo suyo (se corrige) o que la pieza calce con ello
  // sin ser lo mismo (no cambia); y, para un BSD, el aro escrito leído con
  // ISO 5775.
  var fitsCurrent = false;
  final hubDriver = link.bikeFactKey == 'freehubType'
      ? job.hubs[BikeMemoryLocation.rear]?.driver
      : null;
  // El BSD de un neumático lo decide la llanta que instala el mismo trabajo
  // en esa rueda (20260928140000); si no lo dice, no refuta, y la ficha vieja
  // ya no es su rueda.
  final jobRim = link.mustFit && _isWheelBsd(link.bikeFactKey)
      ? job.rimBsd[link.position]
      : null;
  if (jobRim != null &&
      (jobRim.either != null ||
          (jobRim.value != null && jobRim.value != _wholeMeasure(value)))) {
    return withStatus(
      PartBikeFactChangeStatus.incompatible,
      blockingKey:
          '${link.position == BikeMemoryLocation.front ? 'front' : 'rear'}'
          'RimBsdMm',
      blockingValue: '${jobRim.value ?? jobRim.either}',
      blockingSource: 'job_rim',
    );
  }
  if (jobRim != null) {
    // El aro escrito, salvo que la ficha sepa un BSD que no admite (lo que
    // escribió esta misma línea no cuenta): es el aro el que quedó viejo.
    final candidates = isoBsdCandidatesForBikeWheelSize(bikeWheelSize);
    final measured = _wholeMeasure(value);
    final known = _knownFact(current);
    final before = known != null &&
            !(bikeSources[link.bikeFactKey] == 'job_completion' &&
                samePartChangeMarker(
                  writtenMarker,
                  {'key': link.bikeFactKey, 'value': known},
                ))
        ? _wholeMeasure(known)
        : null;
    if (candidates.isNotEmpty &&
        measured != null &&
        !candidates.contains(measured) &&
        (before == null || candidates.contains(before))) {
      return withStatus(
        PartBikeFactChangeStatus.incompatible,
        blockingKey: kBikeWheelSizeFactKey,
        blockingValue: bikeWheelSize!.trim(),
      );
    }
  } else if (link.mustFit && hubDriver != null) {
    if (!_sameFact(hubDriver, value)) {
      if (!link.fitsWith(value, hubDriver)) {
        return withStatus(
          PartBikeFactChangeStatus.incompatible,
          blockingKey: link.bikeFactKey,
          blockingValue: hubDriver,
          blockingSource: 'job_hub',
        );
      }
      fitsCurrent = true;
    }
  } else if (link.mustFit) {
    final known = _knownFact(current);
    var ownWrite = false;
    if (known != null && !_sameFact(known, value)) {
      // Suyo sólo si el servidor lo dice (el último recibo de la bici que
      // tocó la clave es de esta línea): la marca guardada adivinaba mal
      // cuando dos trabajos instalaron la misma medida (revisión de Codex,
      // 2026-09-28). Sin esa lectura, no es suyo.
      ownWrite = bikeSources[link.bikeFactKey] == 'job_completion' &&
          samePartChangeMarker(
            writtenMarker,
            {'key': link.bikeFactKey, 'value': known},
          );
      if (!ownWrite && link.fitsWith(value, known)) {
        fitsCurrent = true;
      } else if (!ownWrite) {
        if (link.bikeFactKey == 'freehubType' &&
            (rearFamilies.contains('hub') ||
                job.hubs.containsKey(BikeMemoryLocation.rear))) {
          return withStatus(
            PartBikeFactChangeStatus.pending,
            blockingKey: link.bikeFactKey,
            blockingValue: '$known',
            pending: PartBikeFactPending.hubChange,
          );
        }
        return withStatus(
          PartBikeFactChangeStatus.incompatible,
          blockingKey: link.bikeFactKey,
          blockingValue: '${_wholeMeasure(known) ?? known}',
        );
      }
    }
    if (_isWheelBsd(link.bikeFactKey) && (known == null || ownWrite)) {
      final candidates = isoBsdCandidatesForBikeWheelSize(bikeWheelSize);
      final measured = _wholeMeasure(value);
      if (candidates.isNotEmpty &&
          measured != null &&
          !candidates.contains(measured)) {
        return withStatus(
          PartBikeFactChangeStatus.incompatible,
          blockingKey: kBikeWheelSizeFactKey,
          blockingValue: bikeWheelSize!.trim(),
        );
      }
    }
  }

  // Lo que sólo se revisa, de la misma familia y rueda: los piñones contra la
  // transmisión; las perforaciones de una maza contra la rueda que queda; el
  // anclaje de un rotor contra el de la maza de su rueda.
  for (final check in links) {
    if (!check.isCheck ||
        check.position != link.position ||
        !check.appliesTo(templateKey)) {
      continue;
    }
    if (_isSpokeHoles(check.bikeFactKey)) {
      final measured = _wholeMeasure(productSpecValues[check.specKey]);
      if (measured == null || !check.accepts(measured)) continue;
      final reference = _wheelSpokes(job, link.position, bikeValues);
      if (reference == null) continue;
      final holes = reference.holes;
      if (holes == null) {
        // El trabajo arma esa rueda con dos cantidades: no calza con ninguna
        // hasta que quede una.
        return withStatus(
          PartBikeFactChangeStatus.incompatible,
          blockingKey: check.bikeFactKey,
          blockingValue: reference.either,
          blockingSource: reference.source,
        );
      }
      if (hubLacingFits(measured, holes)) {
        if (holes != measured) {
          extraNotes.add(_specialLacingNote(measured, holes));
        }
        continue;
      }
      return withStatus(
        PartBikeFactChangeStatus.incompatible,
        blockingKey: check.bikeFactKey,
        blockingValue: '$holes',
        blockingSource: reference.source,
      );
    }
    if (_isRotorMount(check.bikeFactKey)) {
      final mount = check.rawProductValue(productSpecValues)?.toString();
      if (mount == null) continue;
      final wheelHub = job.hubs[link.position];
      final bikeMount = wheelHub != null
          ? wheelHub.rotorMount
          : _knownFact(bikeValues[check.bikeFactKey])?.toString();
      final source = wheelHub != null ? 'job_hub' : null;
      if (bikeMount == null || bikeMount == mount) continue;
      final floating = productSpecValues['rotor_floating'] == true ||
          '${productSpecValues['rotor_floating']}'.toLowerCase() == 'true';
      if (check.fitsWith(mount, bikeMount) && !floating) {
        extraNotes.add(
          'Un rotor de 6 pernos en una maza Center Lock va con el adaptador '
          'Shimano SM-RTAD05.',
        );
        continue;
      }
      if (floating) {
        extraNotes.add(
          'Es flotante (araña de aluminio): el SM-RTAD05 no sirve para él.',
        );
      }
      return withStatus(
        PartBikeFactChangeStatus.incompatible,
        blockingKey: check.bikeFactKey,
        blockingValue: bikeMount,
        blockingSource: source,
      );
    }
    // Una cuenta fuera del rango de la fila (1 a 14) es un error de la ficha
    // técnica, no una transmisión: no refuta.
    final measured = _wholeMeasure(productSpecValues[check.specKey]);
    final product =
        measured != null && check.accepts(measured) ? measured : null;
    final bikeText = bikeValues[check.bikeFactKey]?.toString();
    final bikeCount = check.bikeFactKey == 'drivetrainConfig'
        ? drivetrainRearCogCount(bikeText)
        : _wholeMeasure(bikeText);
    if (product == null || bikeCount == null || product == bikeCount) {
      continue;
    }
    return withStatus(
      rearFamilies.contains('shifter')
          ? PartBikeFactChangeStatus.pending
          : PartBikeFactChangeStatus.incompatible,
      blockingKey: check.bikeFactKey,
      blockingValue: bikeText,
      pending: rearFamilies.contains('shifter')
          ? PartBikeFactPending.shifterChange
          : null,
    );
  }

  if (!samePartChangeMarker(
    confirmedMarker,
    {'key': link.bikeFactKey, 'value': value},
  )) {
    return withStatus(PartBikeFactChangeStatus.unconfirmed);
  }

  if (fitsCurrent) {
    return withStatus(
      PartBikeFactChangeStatus.fits,
      blockingSource: hubDriver != null ? 'job_hub' : null,
      blockingValue: hubDriver,
    );
  }
  return withStatus(_sameFact(_knownFact(current), value)
      ? PartBikeFactChangeStatus.confirms
      : PartBikeFactChangeStatus.change);
}

/// La relación, leída una vez por sesión. Mientras la migración no esté
/// desplegada la tabla no existe: no hay cambios que mostrar ni marcas que
/// guardar, y una línea que ya tenía marca la conserva ([loaded] falso).
class BikeFactSpecLinks {
  BikeFactSpecLinks._();

  static List<BikeFactSpecLink>? _cached;
  static Future<List<BikeFactSpecLink>?>? _loading;

  /// Lo leído, o nulo si todavía no se pudo leer.
  static List<BikeFactSpecLink>? get loaded => _cached;

  static Future<List<BikeFactSpecLink>?> load({SupabaseClient? client}) {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _loading ??= _fetch(client ?? Supabase.instance.client)
        .whenComplete(() => _loading = null);
  }

  static Future<List<BikeFactSpecLink>?> _fetch(SupabaseClient client) async {
    try {
      // Todas las columnas: con sólo 20260928100000 desplegada no existen
      // familia, regla de calce ni mapa de códigos, y una lista explícita
      // haría fallar la lectura entera (una fila sin familia vale para todas;
      // sin regla, es un cambio; sin mapa, una medida).
      final rows = await client.from('bike_fact_spec_links').select();
      return _cached = [
        for (final row in (rows as List).whereType<Map>())
          if (BikeFactSpecLink.fromJson(Map<String, dynamic>.from(row))
              case final link?)
            link,
      ];
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST205' || error.code == '42P01') {
        // Sin la tabla (antes de desplegar) nada propone cambios.
        return _cached = const [];
      }
      debugPrint('⚠️ bike_fact_spec_links: ${error.message}');
      return null;
    } catch (error) {
      debugPrint('⚠️ bike_fact_spec_links: $error');
      return null;
    }
  }

  @visibleForTesting
  static void primeForTesting(List<BikeFactSpecLink>? links) {
    _cached = links;
    _loading = null;
  }
}

/// Lo que cada línea de un trabajo escribió en la ficha y la ficha todavía
/// dice como suyo (`job_part_change_writers_v1`): `{línea: {key, value}}`,
/// o una lista de marcas si la línea escribió varios datos (una maza
/// trasera; 20260928130000). Vacío si la función no existe todavía (antes de
/// desplegar `20260928110000`) o no se pudo leer: entonces ninguna línea se
/// toma como autora y el chip no promete corregir lo que otra escribió.
Future<Map<String, Object>> loadPartChangeWriters(
  String jobId, {
  SupabaseClient? client,
}) async {
  try {
    final rows = await (client ?? Supabase.instance.client)
        .rpc('job_part_change_writers_v1', params: {'p_job_id': jobId});
    if (rows is! Map) return const {};
    return {
      for (final entry in rows.entries)
        if (partChangeMarkerJson(partChangeMarks(entry.value))
            case final marks?)
          entry.key.toString(): marks,
    };
  } catch (error) {
    debugPrint('⚠️ job_part_change_writers_v1: $error');
    return const {};
  }
}
