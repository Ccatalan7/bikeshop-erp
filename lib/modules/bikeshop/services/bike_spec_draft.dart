import 'dart:convert';

import '../config/bike_sheet_options.dart';
import '../config/bottom_bracket_canonical_data.dart';
import '../config/brake_canonical_data.dart';
import '../config/cockpit_canonical_data.dart';
import '../config/drivetrain_canonical_data.dart';
import '../config/wheel_canonical_data.dart';
import '../models/bikeshop_models.dart';

/// Una opción de un dato de la ficha: el código que se guarda, cómo lo dice
/// el taller y, si hace falta, a qué se refiere («Shimano, Tektro, Magura»).
class BikeSpecOption {
  const BikeSpecOption(this.value, this.label, {this.context});

  final String value;
  final String label;
  final String? context;
}

/// Un dato de la ficha técnica que la hoja deja editar en su lugar.
class BikeSpecField {
  const BikeSpecField(this.key, this.label);

  final String key;
  final String label;
}

/// Un sistema de la hoja con todos sus datos, tenga valor o no.
class BikeSpecSection {
  const BikeSpecSection(this.number, this.title, this.fields);

  final int number;
  final String title;
  final List<BikeSpecField> fields;
}

/// La ficha técnica de una bici mientras se edita en la misma hoja que la
/// muestra (dueño, 2026-10-02: «Editar ficha» abría el formulario flotante de
/// crear una bici; tenía que abrirse la misma hoja con lo que falta).
///
/// Aplica las reglas del formulario de la bici (`bike_form_dialog.dart`):
/// lo que el mecánico elige —o confirma eligiendo el mismo valor— queda con
/// origen `mechanic` y confirmado, «Desconocido» se guarda revisado pero
/// nunca confirmado, y lo que un cambio deja sin sentido (la familia de
/// llanta al pasar a disco, los rotores al dejar el disco, las medidas que
/// la nueva caja del pedalier no tiene) se borra con su origen.
///
/// **Sólo se escribe lo que cambió** (revisión de Codex, 2026-10-02): un
/// dato que nadie tocó queda tal como estaba guardado —sin redondear, aunque
/// la regla de hoy lo esconda—, igual que el resto del perfil: ingreso,
/// catálogo y claves que la hoja no conoce.
class BikeSpecDraft {
  BikeSpecDraft._({
    required this.bike,
    required this.profile,
    required Map<String, String?> original,
    required this.legacyDrivetrainConfig,
    required this.legacyDrivetrainSpeeds,
  })  : _original = Map.unmodifiable(original),
        _values = Map.of(original);

  factory BikeSpecDraft.fromRecord({
    required Bike bike,
    BikeProfile? profile,
  }) {
    final values = profile?.technicalValues ?? const <String, dynamic>{};
    String? text(Object? raw) {
      final value = raw?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    String? number(Object? raw) => _formatNumber(_parseDouble(raw));

    final drivetrain = _parseDrivetrain(
      text(values['drivetrainConfig']),
      _parseDouble(values['drivetrainSpeeds'])?.round(),
    );
    final legacyConfig =
        drivetrain == null ? text(values['drivetrainConfig']) : null;
    final legacySpeeds = drivetrain == null
        ? _parseDouble(values['drivetrainSpeeds'])?.round()
        : null;
    final wheelSize = text(bike.wheelSize);
    final spokeFallback = bike.spokeCount?.toString();

    return BikeSpecDraft._(
      bike: bike,
      profile: profile,
      legacyDrivetrainConfig: legacyConfig,
      legacyDrivetrainSpeeds: legacySpeeds,
      original: {
        'bikeType': bike.bikeType?.dbValue,
        'suspensionLayout': text(values['suspensionLayout']),
        'frameSize': text(bike.frameSize),
        'chainrings': drivetrain?.$1.toString(),
        'rearCogs': drivetrain?.$2.toString(),
        'freehubType': text(values['freehubType']),
        'bottomBracketFamily': canonicalBottomBracketFamilyValue(
                text(values['bottomBracketFamily'])) ??
            text(values['bottomBracketFamily']),
        'bbShellWidthMm':
            number(values['bbShellWidthMm'] ?? values['bb_shell_width_mm']),
        'bbShellDiameterMm': number(
            values['bbShellDiameterMm'] ?? values['bb_shell_diameter_mm']),
        'spindleInterface': () {
          final raw = text(values['spindleInterface']) ??
              text(values['spindle_interface']);
          return canonicalBottomBracketSpindleInterfaceValue(raw) ?? raw;
        }(),
        'brakeType': text(values['brakeType']),
        'rimBrakeFamily': text(values['rimBrakeFamily']),
        'frontRotorSizeMm': number(values['frontRotorSizeMm']),
        'rearRotorSizeMm': number(values['rearRotorSizeMm']),
        'frontBrakeFluidType':
            canonicalBrakeFluidTypeValue(text(values['frontBrakeFluidType'])),
        'rearBrakeFluidType':
            canonicalBrakeFluidTypeValue(text(values['rearBrakeFluidType'])),
        // El aro se muestra como lo dice la ficha («29″» y no «29''»); si
        // nadie lo cambia, la bici guarda lo que tenía escrito.
        'wheelSize': canonicalBikeWheelSizeLabel(wheelSize) ?? wheelSize,
        'frontWheelBsdMm': number(values['frontWheelBsdMm']),
        'rearWheelBsdMm': number(values['rearWheelBsdMm']),
        'frontAxleInterface': text(values['frontAxleInterface']),
        'rearAxleInterface': text(values['rearAxleInterface']),
        'frontHubSpacingMm': _formatNumber(bike.frontHubSpacingMm),
        'rearHubSpacingMm': _formatNumber(bike.rearHubSpacingMm),
        // Como el formulario: sin dato por rueda, los rayos de la bici.
        'frontSpokeHoles': number(values['frontSpokeHoles']) ?? spokeFallback,
        'rearSpokeHoles': number(values['rearSpokeHoles']) ?? spokeFallback,
        'valveType': text(values['valveType']),
        'frontRotorMount': text(values['frontRotorMount']),
        'rearRotorMount': text(values['rearRotorMount']),
        // Dirección y cockpit (20261002170000).
        kSteererFitKey: text(values[kSteererFitKey]),
        kHeadsetUpperShisKey: text(values[kHeadsetUpperShisKey]),
        kHeadsetLowerShisKey: text(values[kHeadsetLowerShisKey]),
        kHandlebarClampKey: number(values[kHandlebarClampKey]),
        kControlsBarDiameterKey: number(values[kControlsBarDiameterKey]),
        kSeatpostDiameterKey: number(values[kSeatpostDiameterKey]),
        kSeatpostKindKey: text(values[kSeatpostKindKey]),
      },
    );
  }

  final Bike bike;
  final BikeProfile? profile;

  /// Una transmisión anotada que no se lee como platos × piñones
  /// («interna 3v»): se conserva mientras nadie elija platos y piñones.
  final String? legacyDrivetrainConfig;
  final int? legacyDrivetrainSpeeds;

  final Map<String, String?> _original;
  final Map<String, String?> _values;

  /// Lo que la regla del tipo de bici fijó (una BMX es rígida): se guarda
  /// como sugerencia del tipo, sin confirmar, igual que en el formulario.
  final Set<String> _setByRule = {};

  /// Lo que el mecánico confirmó sin cambiarlo: eligió el mismo valor de un
  /// dato que venía del catálogo o de una sugerencia.
  final Set<String> _reviewed = {};

  static const List<BikeSpecSection> sections = [
    BikeSpecSection(1, 'Cuadro y suspensión', [
      BikeSpecField('bikeType', 'Tipo de bici'),
      BikeSpecField('suspensionLayout', 'Suspensión'),
      BikeSpecField('frameSize', 'Talla'),
    ]),
    BikeSpecSection(2, 'Transmisión', [
      BikeSpecField('chainrings', 'Platos'),
      BikeSpecField('rearCogs', 'Piñones'),
      BikeSpecField('freehubType', 'Driver / freehub'),
    ]),
    BikeSpecSection(3, 'Pedalier', [
      BikeSpecField('bottomBracketFamily', 'Tipo de caja'),
      BikeSpecField('bbShellWidthMm', 'Ancho de caja'),
      BikeSpecField('bbShellDiameterMm', 'Diámetro de caja'),
      BikeSpecField('spindleInterface', 'Interfaz del eje'),
    ]),
    BikeSpecSection(4, 'Frenos', [
      BikeSpecField('brakeType', 'Tipo de freno'),
      BikeSpecField('rimBrakeFamily', 'Freno de llanta'),
      BikeSpecField('frontRotorSizeMm', 'Rotor delantero'),
      BikeSpecField('rearRotorSizeMm', 'Rotor trasero'),
      BikeSpecField('frontBrakeFluidType', 'Fluido delantero'),
      BikeSpecField('rearBrakeFluidType', 'Fluido trasero'),
    ]),
    BikeSpecSection(5, 'Ruedas', [
      BikeSpecField('wheelSize', 'Aro'),
      BikeSpecField('frontWheelBsdMm', 'Llanta delantera (BSD)'),
      BikeSpecField('rearWheelBsdMm', 'Llanta trasera (BSD)'),
      BikeSpecField('frontAxleInterface', 'Eje delantero'),
      BikeSpecField('rearAxleInterface', 'Eje trasero'),
      BikeSpecField('frontHubSpacingMm', 'Maza delantera'),
      BikeSpecField('rearHubSpacingMm', 'Maza trasera'),
      BikeSpecField('frontSpokeHoles', 'Rayos delanteros'),
      BikeSpecField('rearSpokeHoles', 'Rayos traseros'),
      BikeSpecField('valveType', 'Válvula'),
      BikeSpecField('frontRotorMount', 'Anclaje rotor delantero'),
      BikeSpecField('rearRotorMount', 'Anclaje rotor trasero'),
    ]),
    // Los mismos conceptos que el inventario: se llenan con lo que el taller
    // instala (horquilla, manubrio, tija) y se revisan con lo que no cambia la
    // ficha (potencia, manillas, mandos, puños) (20261002170000).
    BikeSpecSection(6, 'Dirección y cockpit', [
      BikeSpecField(kSteererFitKey, 'Tubo de horquilla'),
      BikeSpecField(kHeadsetUpperShisKey, 'Dirección arriba (SHIS)'),
      BikeSpecField(kHeadsetLowerShisKey, 'Dirección abajo (SHIS)'),
      BikeSpecField(kHandlebarClampKey, 'Manubrio (abrazadera)'),
      BikeSpecField(kControlsBarDiameterKey, 'Zona de mandos'),
      BikeSpecField(kSeatpostDiameterKey, 'Tija'),
      BikeSpecField(kSeatpostKindKey, 'Tipo de tija'),
    ]),
  ];

  /// Las medidas con décimas de la sección 6: se guardan como número, sin
  /// redondear.
  static const Set<String> _decimalMeasureKeys = {
    kHandlebarClampKey,
    kControlsBarDiameterKey,
    kSeatpostDiameterKey,
  };

  /// Las claves del perfil que esta hoja escribe; las mismas que el
  /// formulario de la bici, con los alias antiguos del pedalier.
  static const Set<String> managedTechnicalKeys = {
    'suspensionLayout',
    'brakeType',
    'rimBrakeFamily',
    'freehubType',
    'valveType',
    'bottomBracketFamily',
    'bbShellWidthMm',
    'bb_shell_width_mm',
    'bbShellDiameterMm',
    'bb_shell_diameter_mm',
    'spindleInterface',
    'spindle_interface',
    'frontSpokeHoles',
    'rearSpokeHoles',
    'frontRotorSizeMm',
    'rearRotorSizeMm',
    'frontWheelBsdMm',
    'rearWheelBsdMm',
    'frontBrakeFluidType',
    'rearBrakeFluidType',
    'frontAxleInterface',
    'rearAxleInterface',
    'frontRotorMount',
    'rearRotorMount',
    'drivetrainSpeeds',
    'drivetrainConfig',
    kSteererFitKey,
    kHeadsetUpperShisKey,
    kHeadsetLowerShisKey,
    kHandlebarClampKey,
    kControlsBarDiameterKey,
    kSeatpostDiameterKey,
    kSeatpostKindKey,
  };

  /// Los nombres antiguos de tres datos del pedalier, que todavía se leen.
  static const Map<String, String> _legacyAliases = {
    'bbShellWidthMm': 'bb_shell_width_mm',
    'bbShellDiameterMm': 'bb_shell_diameter_mm',
    'spindleInterface': 'spindle_interface',
  };

  /// Los datos base que viven en `bikes` y cuyo origen va en la ficha.
  static const Set<String> baseFactKeys = {
    'wheelSize',
    'bikeType',
    'frontHubSpacingMm',
    'rearHubSpacingMm',
  };

  String? value(String key) => _values[key];
  String? originalValue(String key) => _original[key];

  bool isChanged(String key) => _values[key] != _original[key];

  /// Confirmado en esta edición sin cambiar su valor.
  bool isReviewed(String key) => !isChanged(key) && _reviewed.contains(key);

  /// Lo que se guarda: lo cambiado y lo confirmado sin cambiar.
  Set<String> get changedKeys => {
        for (final key in _values.keys)
          if (isChanged(key) || isReviewed(key)) key,
      };

  int get changeCount => changedKeys.length;

  bool get hasChanges => changeCount > 0;

  /// La clave de la ficha que guarda el origen de [key].
  static String sourceKeyFor(String key) => switch (key) {
        'chainrings' || 'rearCogs' => 'drivetrainConfig',
        _ => key,
      };

  /// Si la ficha ya tiene [key] confirmado (antes de esta edición).
  bool isConfirmedOnRecord(String key) =>
      profile?.technicalConfirmed[sourceKeyFor(key)] == true;

  /// Si tiene sentido ofrecer «Confirmar» para [key]: tiene un valor que
  /// nadie confirmó y que no es «Desconocido» (eso nunca se confirma).
  bool canReview(String key) {
    final value = _values[key];
    return key != 'frameSize' &&
        value != null &&
        value != 'unknown' &&
        value != kRegistryUnknownCode &&
        !isChanged(key) &&
        !isReviewed(key) &&
        !isConfirmedOnRecord(key);
  }

  /// Confirma [key] tal como está.
  void review(String key) {
    if (_values[key] == null) return;
    _reviewed.add(key);
  }

  bool get _isDisc =>
      _values['brakeType'] == 'mechanical_disc' ||
      _values['brakeType'] == 'hydraulic_disc';

  /// Si la hoja muestra [key] con lo que ya está elegido. Lo que se esconde
  /// tampoco se guarda.
  bool isVisible(String key) {
    final family = _values['bottomBracketFamily'];
    return switch (key) {
      'rimBrakeFamily' => _values['brakeType'] == 'rim',
      'frontRotorSizeMm' || 'rearRotorSizeMm' => _isDisc,
      // El fluido es de cada freno; con otro freno se muestra si la ficha
      // ya lo dice (los hay de llanta hidráulicos).
      'frontBrakeFluidType' ||
      'rearBrakeFluidType' =>
        _values['brakeType'] == 'hydraulic_disc' ||
            _values[key] != null ||
            _original[key] != null,
      'bbShellWidthMm' ||
      'spindleInterface' =>
        isKnownBottomBracketFamily(family),
      'bbShellDiameterMm' => bottomBracketFamilyUsesShellDiameter(family),
      'frontRotorMount' ||
      'rearRotorMount' =>
        _isDisc || _values[key] != null || _original[key] != null,
      _ => true,
    };
  }

  /// Los datos de [section] que la hoja muestra con lo que ya está elegido.
  List<BikeSpecField> visibleFields(BikeSpecSection section) => [
        for (final field in section.fields)
          if (isVisible(field.key)) field,
      ];

  /// Las opciones de [key], con lo que ya tiene la bici aunque no esté en la
  /// lista (un dato antiguo no desaparece por abrir la hoja).
  List<BikeSpecOption> options(String key) {
    final base = _baseOptions(key);
    final current = _values[key];
    if (current == null || base.any((option) => option.value == current)) {
      return base;
    }
    return [...base, BikeSpecOption(current, labelFor(key, current))];
  }

  List<BikeSpecOption> _baseOptions(String key) {
    List<BikeSpecOption> fromMap(Map<String, String> map) => [
          for (final entry in map.entries)
            BikeSpecOption(entry.key, entry.value),
        ];
    List<BikeSpecOption> millimeters(List<int> values) => [
          for (final value in values) BikeSpecOption('$value', '$value mm'),
        ];
    return switch (key) {
      'bikeType' => [
          for (final type in BikeType.values)
            BikeSpecOption(type.dbValue, type.displayName),
        ],
      'suspensionLayout' => () {
          final allowed = allowedSuspensionLayoutsForBikeType(
              BikeType.fromDbValue(_values['bikeType']));
          return [
            for (final entry in kBikeSuspensionLayoutOptions.entries)
              if (allowed == null || allowed.contains(entry.key))
                BikeSpecOption(entry.key, entry.value),
          ];
        }(),
      'frameSize' => [
          for (final size in kBikeFrameSizeOptions)
            if (size != 'Otra') BikeSpecOption(size, size),
        ],
      'chainrings' => fromMap(kDrivetrainFrontChainringCountOptions),
      'rearCogs' => fromMap(kDrivetrainRearCogCountOptions),
      'freehubType' => fromMap(kDrivetrainFreehubTypeOptions),
      'bottomBracketFamily' => fromMap(kBottomBracketFamilyOptions),
      'bbShellWidthMm' => fromMap(bottomBracketShellWidthOptionsForFamily(
          _values['bottomBracketFamily'])),
      'bbShellDiameterMm' => fromMap(bottomBracketShellDiameterOptionsForFamily(
          _values['bottomBracketFamily'])),
      'spindleInterface' => fromMap(
          bottomBracketSpindleInterfaceOptionsForFamily(
              _values['bottomBracketFamily'])),
      'brakeType' => fromMap(kBikeProfileBrakeTypeOptions),
      'rimBrakeFamily' => fromMap(kRimBrakeFamilyOptions),
      'frontRotorSizeMm' ||
      'rearRotorSizeMm' =>
        millimeters(kBikeRotorSizeOptions),
      'frontBrakeFluidType' || 'rearBrakeFluidType' => [
          for (final entry in kBrakeFluidTypeLabels.entries)
            BikeSpecOption(
              entry.key,
              entry.value,
              context: _fluidBrands[entry.key],
            ),
        ],
      'wheelSize' => [
          for (final size in kBikeWheelSizeOptions)
            if (size != 'Otra') BikeSpecOption(size, size),
        ],
      'frontWheelBsdMm' || 'rearWheelBsdMm' => [
          for (final bsd in kIsoWheelBsdOptions)
            BikeSpecOption('$bsd', isoWheelBsdLabel(bsd)),
        ],
      'frontAxleInterface' ||
      'rearAxleInterface' =>
        fromMap(kBikeAxleInterfaceOptions),
      'frontHubSpacingMm' => millimeters(kBikeFrontHubSpacingOptions),
      'rearHubSpacingMm' => millimeters(kBikeRearHubSpacingOptions),
      'frontSpokeHoles' || 'rearSpokeHoles' => [
          for (final holes in kBikeSpokeHoleOptions)
            BikeSpecOption('$holes', '$holes'),
        ],
      'valveType' => fromMap(kBikeValveTypeOptions),
      'frontRotorMount' ||
      'rearRotorMount' =>
        fromMap(kBikeRotorMountChoiceOptions),
      kSteererFitKey => fromMap(kSteererFitLabels),
      kHeadsetUpperShisKey => [
          for (final code in kHeadsetUpperShisOptions)
            BikeSpecOption(code, code),
        ],
      kHeadsetLowerShisKey => [
          for (final code in kHeadsetLowerShisOptions)
            BikeSpecOption(code, code),
        ],
      kHandlebarClampKey => _millimeterOptions(kHandlebarClampOptions),
      kControlsBarDiameterKey => [
          for (final value in kControlsBarDiameterOptions)
            BikeSpecOption(
              _formatNumber(value)!,
              cockpitMillimeters(value),
              context: kControlsBarDiameterContext[_formatNumber(value)],
            ),
        ],
      kSeatpostDiameterKey => _millimeterOptions(kSeatpostDiameterOptions),
      kSeatpostKindKey => fromMap(kSeatpostKindLabels),
      _ => const [],
    };
  }

  static List<BikeSpecOption> _millimeterOptions(List<double> values) => [
        for (final value in values)
          BikeSpecOption(_formatNumber(value)!, cockpitMillimeters(value)),
      ];

  /// Lo que sugiere el tipo de bici para [key] mientras la ficha no lo
  /// dice: la zona de mandos de un manubrio de ruta o uno plano. Se usa con
  /// «Usar»; sola no se guarda.
  String? suggestion(String key) {
    if (key != kControlsBarDiameterKey || _values[key] != null) return null;
    final suggested = suggestedControlsBarDiameterForBikeType(
        BikeType.fromDbValue(_values['bikeType']));
    return suggested == null ? null : _formatNumber(suggested);
  }

  static const Map<String, String> _fluidBrands = {
    'aceite_mineral': 'Shimano, Tektro, Magura',
    'dot_5_1': 'SRAM, Hayes, Hope',
  };

  /// Cómo se dice [value] de [key] en el taller.
  String labelFor(String key, String value) {
    for (final option in _baseOptions(key)) {
      if (option.value == value) return option.label;
    }
    return switch (key) {
      'frontHubSpacingMm' ||
      'rearHubSpacingMm' ||
      'bbShellWidthMm' ||
      'bbShellDiameterMm' ||
      'frontRotorSizeMm' ||
      'rearRotorSizeMm' =>
        '$value mm',
      kHandlebarClampKey ||
      kControlsBarDiameterKey ||
      kSeatpostDiameterKey =>
        double.tryParse(value) == null
            ? value
            : cockpitMillimeters(double.parse(value)),
      'frontWheelBsdMm' || 'rearWheelBsdMm' => int.tryParse(value) == null
          ? value
          : isoWheelBsdLabel(int.parse(value)),
      _ => value,
    };
  }

  /// Cambia [key]. Lo que depende de él se ajusta como en el formulario.
  /// Elegir el mismo valor que tenía lo confirma, como en el formulario.
  void set(String key, String? value) {
    if (value != null && value == _values[key]) {
      if (!isChanged(key) && !isConfirmedOnRecord(key)) review(key);
      return;
    }
    _values[key] = value;
    _reviewed.remove(key);
    _setByRule.remove(key);
    switch (key) {
      case 'bikeType':
        final allowed =
            allowedSuspensionLayoutsForBikeType(BikeType.fromDbValue(value));
        final suspension = _values['suspensionLayout'];
        if (allowed != null &&
            suspension != null &&
            !allowed.contains(suspension)) {
          if (allowed.length == 1) {
            _values['suspensionLayout'] = allowed.single;
            _setByRule.add('suspensionLayout');
          } else {
            _values['suspensionLayout'] = null;
          }
        }
      case 'brakeType':
        if (value != 'rim') _values['rimBrakeFamily'] = null;
        if (!_isDisc) {
          _values['frontRotorSizeMm'] = null;
          _values['rearRotorSizeMm'] = null;
        }
      case 'bottomBracketFamily':
        for (final dependent in const [
          'bbShellWidthMm',
          'bbShellDiameterMm',
          'spindleInterface',
        ]) {
          final current = _values[dependent];
          if (current == null) continue;
          if (!isVisible(dependent) ||
              !_baseOptions(dependent).any((o) => o.value == current)) {
            _values[dependent] = null;
          }
        }
    }
  }

  /// Vuelve [key] a lo que tenía la ficha, sin confirmarlo.
  void revert(String key) {
    set(key, _original[key]);
    _reviewed.remove(key);
  }

  /// Lo que impide guardar, dicho para el mecánico; `null` si se puede.
  String? get blockingMessage {
    final chainrings = _values['chainrings'];
    final cogs = _values['rearCogs'];
    if ((chainrings == null) != (cogs == null) &&
        (isChanged('chainrings') || isChanged('rearCogs'))) {
      return 'Elige platos y piñones juntos: la transmisión se guarda '
          'entera (por ejemplo 2×10).';
    }
    return null;
  }

  /// La transmisión que queda: «2×10 · 20 velocidades», o lo anotado si no
  /// se lee como platos × piñones.
  String? get drivetrainSummary {
    final chainrings = int.tryParse(_values['chainrings'] ?? '');
    final cogs = int.tryParse(_values['rearCogs'] ?? '');
    if (chainrings != null && cogs != null) {
      if (chainrings == 1 && cogs == 1) return 'Una velocidad';
      return '$chainrings×$cogs · ${chainrings * cogs} velocidades';
    }
    if (chainrings == null && cogs == null) {
      final legacy = legacyDrivetrainConfig;
      final speeds = legacyDrivetrainSpeeds;
      if (legacy != null || speeds != null) {
        return [
          if (legacy != null) 'Anotado «$legacy»',
          if (speeds != null) '$speeds velocidades',
        ].join(' · ');
      }
    }
    return null;
  }

  /// La bici y el perfil como quedan, para `saveBikeAggregate`.
  ({Bike bike, BikeProfile? profile}) build({required DateTime confirmedAt}) {
    final bikeJson = bike.toJson();
    void base(String key, String column, Object? Function(String?) convert) {
      if (isChanged(key)) bikeJson[column] = convert(_values[key]);
    }

    base('bikeType', 'bike_type', (value) => value);
    base('frameSize', 'frame_size', (value) => value);
    base('wheelSize', 'wheel_size', (value) => value);
    base('frontHubSpacingMm', 'front_hub_spacing_mm', _parseDouble);
    base('rearHubSpacingMm', 'rear_hub_spacing_mm', _parseDouble);
    if (isChanged('frontSpokeHoles') || isChanged('rearSpokeHoles')) {
      final front = int.tryParse(_values['frontSpokeHoles'] ?? '');
      final rear = int.tryParse(_values['rearSpokeHoles'] ?? '');
      bikeJson['spoke_count'] = front ?? rear;
    }
    final savedBike = Bike.fromJson(bikeJson);

    final technicalValues =
        Map<String, dynamic>.from(profile?.technicalValues ?? const {});
    // Un cambio escribe su valor (o lo borra); lo que nadie cambió queda
    // como estaba. `set` ya vació lo que un cambio dejó sin sentido.
    void put(String key, Object? value, {List<String> aliases = const []}) {
      for (final alias in aliases) {
        technicalValues.remove(alias);
      }
      if (value == null) {
        technicalValues.remove(key);
      } else {
        technicalValues[key] = value;
      }
    }

    String? shown(String key) => isVisible(key) ? _values[key] : null;
    // Se escribe lo cambiado, y lo confirmado que la ficha no guarda con su
    // propia clave (venía de un nombre antiguo o de los rayos de la bici):
    // confirmar es afirmar ese valor, que tiene que quedar escrito.
    bool writes(String key) =>
        isChanged(key) ||
        (isReviewed(key) &&
            !(profile?.technicalValues.containsKey(sourceKeyFor(key)) ??
                false));
    for (final key in const [
      'suspensionLayout',
      'brakeType',
      'rimBrakeFamily',
      'freehubType',
      'valveType',
      'bottomBracketFamily',
      'frontBrakeFluidType',
      'rearBrakeFluidType',
      'frontAxleInterface',
      'rearAxleInterface',
      'frontRotorMount',
      'rearRotorMount',
      kSteererFitKey,
      kHeadsetUpperShisKey,
      kHeadsetLowerShisKey,
      kSeatpostKindKey,
    ]) {
      if (writes(key)) put(key, shown(key));
    }
    for (final key in _decimalMeasureKeys) {
      if (writes(key)) put(key, _parseDouble(shown(key)));
    }
    if (writes('spindleInterface')) {
      put('spindleInterface', shown('spindleInterface'),
          aliases: const ['spindle_interface']);
    }
    if (writes('bbShellWidthMm')) {
      put('bbShellWidthMm', _parseDouble(shown('bbShellWidthMm')),
          aliases: const ['bb_shell_width_mm']);
    }
    if (writes('bbShellDiameterMm')) {
      put('bbShellDiameterMm', _parseDouble(shown('bbShellDiameterMm')),
          aliases: const ['bb_shell_diameter_mm']);
    }
    for (final key in const [
      'frontRotorSizeMm',
      'rearRotorSizeMm',
      'frontWheelBsdMm',
      'rearWheelBsdMm',
    ]) {
      if (writes(key)) put(key, _parseDouble(shown(key))?.round());
    }
    // Los rayos de una rueda sin dato propio se leen de los de la bici, que
    // cambian con éstos: al tocar una se escriben las dos, como el
    // formulario, para que la otra no pase a leer el número nuevo.
    if (writes('frontSpokeHoles') || writes('rearSpokeHoles')) {
      for (final key in const ['frontSpokeHoles', 'rearSpokeHoles']) {
        put(key, _parseDouble(shown(key))?.round());
      }
    }
    if (writes('chainrings') || writes('rearCogs')) {
      final chainrings = int.tryParse(_values['chainrings'] ?? '');
      final cogs = int.tryParse(_values['rearCogs'] ?? '');
      final complete = chainrings != null && cogs != null;
      put(
        'drivetrainConfig',
        !complete
            ? null
            : (chainrings == 1 && cogs == 1
                ? 'singlespeed'
                : '${chainrings}x$cogs'),
      );
      put('drivetrainSpeeds', complete ? chainrings * cogs : null);
    }

    final existing = profile;
    if (existing == null &&
        technicalValues.isEmpty &&
        !changedKeys.any(baseFactKeys.contains)) {
      return (bike: savedBike, profile: null);
    }

    final sources = Map<String, dynamic>.from(existing?.technicalSources ?? {});
    final confirmed =
        Map<String, dynamic>.from(existing?.technicalConfirmed ?? {});
    void mark(String key, {required bool byRule}) {
      sources[key] = byRule ? 'bike_type' : 'mechanic';
      confirmed[key] = !byRule;
    }

    // Un valor guardado con un nombre antiguo del pedalier sigue siendo ese
    // dato: sus marcas no se borran porque falte la clave nueva.
    String? storedKeyOf(String key) {
      if (technicalValues.containsKey(key)) return key;
      final alias = _legacyAliases[key];
      return alias != null && technicalValues.containsKey(alias) ? alias : null;
    }

    for (final key in changedKeys) {
      if (storedKeyOf(sourceKeyFor(key)) == null &&
          !baseFactKeys.contains(key)) {
        continue;
      }
      switch (key) {
        case 'chainrings' || 'rearCogs':
          mark('drivetrainConfig', byRule: false);
          mark('drivetrainSpeeds', byRule: false);
        case 'frameSize':
          break;
        default:
          mark(key, byRule: _setByRule.contains(key));
      }
    }

    final baseFactPresent = <String, bool>{
      'wheelSize': savedBike.wheelSize?.trim().isNotEmpty ?? false,
      'bikeType': savedBike.bikeType != null,
      'frontHubSpacingMm': savedBike.frontHubSpacingMm != null,
      'rearHubSpacingMm': savedBike.rearHubSpacingMm != null,
    };
    bool baseFactGone(String key) =>
        baseFactKeys.contains(key) && baseFactPresent[key] != true;
    sources.removeWhere((key, _) =>
        (managedTechnicalKeys.contains(key) && storedKeyOf(key) == null) ||
        baseFactGone(key));
    // «Desconocido» queda revisado por el mecánico, nunca confirmado.
    confirmed.removeWhere((key, _) {
      if (baseFactGone(key)) return true;
      if (!managedTechnicalKeys.contains(key)) return false;
      final stored = storedKeyOf(key);
      return stored == null ||
          technicalValues[stored] == 'unknown' ||
          technicalValues[stored] == kRegistryUnknownCode;
    });

    final intakeProfile =
        Map<String, dynamic>.from(existing?.intakeProfile ?? const {});
    final technicalProfile =
        Map<String, dynamic>.from(existing?.technicalProfile ?? const {})
          ..['values'] = technicalValues
          ..['sources'] = sources
          ..['confirmed'] = confirmed;
    return (
      bike: savedBike,
      profile: BikeProfile(
        id: existing?.id,
        tenantId: savedBike.tenantId,
        bikeId: savedBike.id!,
        catalogBikeId: existing?.catalogBikeId,
        intakeProfile: intakeProfile,
        technicalProfile: technicalProfile,
        summarySnapshot: {
          ...?existing?.summarySnapshot,
          ...BikeProfileSummaryBuilder.buildSummarySnapshot(
            bike: savedBike,
            intakeProfile: intakeProfile,
            technicalValues: technicalValues,
            lastConfirmedAt: confirmedAt,
          ),
        },
        lastConfirmedAt: confirmedAt,
        createdAt: existing?.createdAt,
        updatedAt: existing?.updatedAt,
      ),
    );
  }

  /// La firma de lo que se manda: con la misma firma, un reintento usa la
  /// misma llave de operación y el servidor no lo aplica dos veces.
  String contentSignature(Bike saved, BikeProfile? savedProfile) {
    final payload = Map<String, dynamic>.from(saved.toJson())
      ..remove('id')
      ..remove('tenant_id')
      ..remove('customer_id')
      ..remove('created_at')
      ..remove('updated_at');
    return jsonEncode(<String, dynamic>{
      'bike_id': saved.id,
      'customer_id': saved.customerId,
      'expected_bike_updated_at': bike.updatedAt.toUtc().toIso8601String(),
      'expected_profile_updated_at':
          profile?.updatedAt.toUtc().toIso8601String(),
      'bike': payload,
      'profile': savedProfile == null
          ? null
          : <String, dynamic>{
              'id': savedProfile.id,
              'catalog_bike_id': savedProfile.catalogBikeId,
              'intake_profile': savedProfile.intakeProfile,
              'technical_profile': savedProfile.technicalProfile,
            },
    });
  }

  /// La misma ficha sobre una versión más nueva de la bici: lo que el
  /// mecánico cambió se vuelve a aplicar encima (un guardado rechazado por un
  /// cambio ajeno no le hace repetir su trabajo).
  BikeSpecDraft rebasedOn({required Bike bike, BikeProfile? profile}) {
    final fresh = BikeSpecDraft.fromRecord(bike: bike, profile: profile);
    for (final key in _orderedKeys) {
      if (isChanged(key)) fresh.set(key, _values[key]);
    }
    fresh._setByRule.addAll(_setByRule.where(fresh.isChanged));
    for (final key in _reviewed) {
      if (fresh.value(key) == _values[key]) fresh.review(key);
    }
    return fresh;
  }

  /// Los que mandan sobre otros primero, para que una regla no borre lo que
  /// el mecánico eligió después.
  static final List<String> _orderedKeys = [
    'bikeType',
    'brakeType',
    'bottomBracketFamily',
    for (final section in sections)
      for (final field in section.fields)
        if (!const {'bikeType', 'brakeType', 'bottomBracketFamily'}
            .contains(field.key))
          field.key,
  ];
}

double? _parseDouble(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString().trim().replaceAll(',', '.'));
}

/// «68», «86.5», «41.9614»: el número entero como está guardado. Se muestra
/// completo porque confirmarlo afirma ese valor, no uno redondeado.
String? _formatNumber(double? value) {
  if (value == null) return null;
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

/// Platos y piñones de lo anotado: «2x10», «singlespeed» o «2x» con las
/// velocidades. La misma lectura que el formulario de la bici.
(int, int)? _parseDrivetrain(String? config, int? speeds) {
  final normalized = config?.toLowerCase().replaceAll(' ', '');
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized == 'singlespeed' ||
      normalized == 'single_speed' ||
      normalized == 'single-speed' ||
      normalized.contains('fixie')) {
    return (1, 1);
  }
  final full = RegExp(r'^(\d+)x(\d+)$').firstMatch(normalized);
  if (full != null) {
    return (int.parse(full.group(1)!), int.parse(full.group(2)!));
  }
  final partial = RegExp(r'^(\d+)x$').firstMatch(normalized);
  if (partial != null && speeds != null) {
    final front = int.parse(partial.group(1)!);
    if (front > 0 && speeds % front == 0) return (front, speeds ~/ front);
  }
  return null;
}
