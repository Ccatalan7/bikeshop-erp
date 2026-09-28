/// Contrato de las preguntas de «Configurar»: a qué capa del backbone
/// pertenece cada respuesta.
///
/// `BIKE_WORKSHOP_MASTER_SCHEMA.md` prohíbe que el wizard de servicio sea una
/// verdad paralela. Cada pregunta viva tiene un solo destino:
///
/// - [ServiceQuestionDestination.lineTarget]: a qué rueda o lado aplica la
///   línea (`mechanic_job_items.location_key`).
/// - [ServiceQuestionDestination.bikeProfile]: verdad durable de la bici
///   (`bike_profiles.technical_profile.values` o una columna de `bikes`). Lo
///   que la bici **ya tiene** (observado) se confirma al guardar el trabajo; lo
///   que el servicio **deja instalado**
///   ([ServiceQuestionContract.appliesOnCompletion]) cambia la ficha recién al
///   terminar el trabajo, nunca al configurarlo.
/// - [ServiceQuestionDestination.diagnosis]: hallazgo de la visita
///   (`mechanic_job_bikes.diagnosis_sheet_data`), el mismo campo que edita la
///   pestaña Diagnóstico.
/// - [ServiceQuestionDestination.serviceExecution]: sólo sirve para ejecutar
///   ese servicio (`mechanic_job_items.service_configuration_data`).
///
/// [ServiceQuestionContract.honored] dice si el código de hoy cumple ese
/// destino. Es el libro de avance: cuando un paso del backbone cierra una
/// brecha, se cambia aquí y en el documento maestro en la misma tarea.
library;

/// Dónde vive, decidido en el paso F (2026-09-27, con Park Tool y Sheldon
/// Brown), una respuesta que hoy queda como propia del servicio y parecía un
/// dato de la bici.
enum UpstreamDecision {
  /// Dato de la bici (cuadro, horquilla o sistema instalado) que la ficha
  /// debe representar; la clave propuesta va en `upstreamCandidate`.
  bikeFact,

  /// Propiedad de la pieza instalada: llega a la matriz por el producto
  /// (`bike_component_lifecycles` → ficha técnica del producto), no por la
  /// ficha de la bici.
  componentSpec,

  /// Hallazgo de la visita: diagnóstico o ejecución, nunca la ficha.
  visitFinding,
}

enum ServiceQuestionDestination {
  lineTarget,
  bikeProfile,
  diagnosis,
  serviceExecution,
}

class ServiceQuestionContract {
  const ServiceQuestionContract({
    required this.family,
    required this.key,
    required this.destination,
    required this.honored,
    this.profileKey,
    this.profileKeyByLocation,
    this.diagnosisSystem,
    this.diagnosisField,
    this.gap,
    this.upstreamCandidate,
    this.appliesOnCompletion = false,
    this.upstreamDecision,
  });

  /// `service_profiles.service_family` tal como vive en producción.
  final String family;

  /// `service_profile_questions.key`.
  final String key;

  final ServiceQuestionDestination destination;

  /// Si el código de hoy lee y escribe (o proyecta) donde corresponde.
  final bool honored;

  /// Clave de la ficha cuando no depende de la rueda. Las que viven en una
  /// columna de `bikes` llevan el prefijo `bikes.`.
  final String? profileKey;

  /// Clave de la ficha cuando depende de la rueda de la línea.
  final Map<String, String>? profileKeyByLocation;

  /// Sistema del diagnóstico: `brake`, `drivetrain`, `wheel`,
  /// `bottom_bracket` o `cockpit`. Con `brake` y `wheel` la rueda de la línea
  /// elige delantero o trasero.
  final String? diagnosisSystem;

  /// Campo de ese sistema en `MechanicJobDiagnosisSheet`.
  final String? diagnosisField;

  /// Qué falta para cumplir el destino, cuando [honored] es falso.
  final String? gap;

  /// Hecho durable que la ficha todavía no representa. Queda como
  /// [ServiceQuestionDestination.serviceExecution] hasta que se decida su
  /// clave upstream (paso F del documento maestro); nunca se inventa una.
  final String? upstreamCandidate;

  /// La respuesta describe lo que el servicio deja instalado (la rueda que se
  /// arma), no la bici como llegó: la ficha la toma al terminar el trabajo,
  /// con fuente `job_completion`. Sólo con destino ficha.
  final bool appliesOnCompletion;

  /// Decisión del paso F para un [upstreamCandidate].
  final UpstreamDecision? upstreamDecision;
}

const _lineTarget = ServiceQuestionDestination.lineTarget;
const _profile = ServiceQuestionDestination.bikeProfile;
const _diagnosis = ServiceQuestionDestination.diagnosis;
const _execution = ServiceQuestionDestination.serviceExecution;

const _spokeHoles = {'front': 'frontSpokeHoles', 'rear': 'rearSpokeHoles'};
const _rotorSize = {'front': 'frontRotorSizeMm', 'rear': 'rearRotorSizeMm'};
const _brakeFluid = {
  'front': 'frontBrakeFluidType',
  'rear': 'rearBrakeFluidType',
};
const _axleInterface = {
  'front': 'frontAxleInterface',
  'rear': 'rearAxleInterface',
};

/// Un contrato por par familia/clave: los 15 perfiles con mapeo activo suman
/// 76 preguntas y 56 pares, leídos de producción el 2026-09-27
/// (`test/fixtures/bike_workshop/live_service_questions_2026-09-27.json`).
const List<ServiceQuestionContract> kServiceQuestionContracts = [
  // ── Frenos ──────────────────────────────────────────────────────────────
  ServiceQuestionContract(
    family: 'brake',
    key: 'which_wheel',
    destination: _lineTarget,
    // `both` no divide la línea (queda `none`): `serviceWheelPositions` la
    // lleva a los dos frenos en el diagnóstico y en la memoria (paso C).
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'brake_type',
    destination: _profile,
    profileKey: 'brakeType',
    // Dato de la bici completa: una rueda sugiere, ambas confirman
    // (`brakeServiceFacts`, paso D).
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'rotor_size',
    destination: _profile,
    profileKeyByLocation: _rotorSize,
    // El rotor que ya está puesto: se confirma con esa rueda; un solo tamaño
    // para «ambas» no se escribe (paso D).
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'symptom',
    destination: _diagnosis,
    diagnosisSystem: 'brake',
    diagnosisField: 'symptomKeys',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'pad_condition',
    destination: _diagnosis,
    diagnosisSystem: 'brake',
    diagnosisField: 'padWearPercent',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'pad_contaminated',
    destination: _diagnosis,
    diagnosisSystem: 'brake',
    diagnosisField: 'padContaminationStatus',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'rotor_condition',
    destination: _diagnosis,
    diagnosisSystem: 'brake',
    diagnosisField: 'rotorTruenessStatus',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'damage_level',
    destination: _diagnosis,
    diagnosisSystem: 'brake',
    diagnosisField: 'rotorTruenessStatus',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'contamination_level',
    destination: _diagnosis,
    diagnosisSystem: 'brake',
    diagnosisField: 'padContaminationStatus',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'fluid_type',
    destination: _profile,
    profileKeyByLocation: _brakeFluid,
    // Park Tool y SRAM: no se mezclan fluidos dentro de un sistema, y cada
    // freno es su propio sistema (manilla, manguera y caliper). Se confirma
    // con el freno que se sangra (paso F.2, corregido el 2026-09-27).
    // Códigos del registro `fluid_type`.
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'piston_count',
    destination: _execution,
    honored: true,
    upstreamCandidate: 'pistones del caliper instalado, por rueda',
    upstreamDecision: UpstreamDecision.componentSpec,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'include_pads',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'fluid_check',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'replace_parts',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'replace_pads',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'brake',
    key: 'replace_seals',
    destination: _execution,
    honored: true,
  ),

  // ── Transmisión ─────────────────────────────────────────────────────────
  ServiceQuestionContract(
    family: 'drivetrain',
    key: 'front_chainring_count',
    destination: _profile,
    profileKey: 'drivetrainConfig',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'drivetrain',
    key: 'rear_cog_count',
    destination: _profile,
    profileKey: 'drivetrainSpeeds',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'drivetrain',
    key: 'freehub_type',
    destination: _profile,
    profileKey: 'freehubType',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'drivetrain',
    key: 'cable_condition',
    destination: _diagnosis,
    diagnosisSystem: 'drivetrain',
    diagnosisField: 'cableCondition',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'drivetrain',
    key: 'chain_wear',
    destination: _diagnosis,
    diagnosisSystem: 'drivetrain',
    diagnosisField: 'chainWearPercent',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'drivetrain',
    key: 'derailleurs',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'drivetrain',
    key: 'include_housing',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'drivetrain',
    key: 'lube_type',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'drivetrain',
    key: 'derailleur_check',
    destination: _execution,
    honored: true,
  ),

  // ── Pedalier ────────────────────────────────────────────────────────────
  ServiceQuestionContract(
    family: 'bottom_bracket',
    key: 'bottom_bracket_family',
    destination: _profile,
    profileKey: 'bottomBracketFamily',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'bottom_bracket',
    key: 'bb_shell_width_mm',
    destination: _profile,
    profileKey: 'bbShellWidthMm',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'bottom_bracket',
    key: 'bb_shell_diameter_mm',
    destination: _profile,
    profileKey: 'bbShellDiameterMm',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'bottom_bracket',
    key: 'spindle_interface',
    destination: _profile,
    profileKey: 'spindleInterface',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'bottom_bracket',
    key: 'symptom',
    destination: _diagnosis,
    diagnosisSystem: 'bottom_bracket',
    diagnosisField: 'bearingCondition',
    // Juego, aspereza y apretado van al rodamiento; ruido al estado de ruido;
    // preventivo no es un hallazgo (`bearingSymptomFindings`, paso E).
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'bottom_bracket',
    key: 'replace_unit',
    destination: _execution,
    honored: true,
  ),

  // ── Dirección ───────────────────────────────────────────────────────────
  ServiceQuestionContract(
    family: 'cockpit',
    key: 'symptom',
    destination: _diagnosis,
    diagnosisSystem: 'cockpit',
    diagnosisField: 'headsetBearingCondition',
    // Igual que el pedalier, contra la caja de dirección (paso E).
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'cockpit',
    key: 'crown_race_condition',
    destination: _execution,
    honored: true,
    // Park Tool: una dirección picada se reemplaza. Es estado de la visita;
    // el diagnóstico de dirección no tiene campo de pistas todavía.
    upstreamCandidate: 'estado de la pista de corona',
    upstreamDecision: UpstreamDecision.visitFinding,
  ),
  ServiceQuestionContract(
    family: 'cockpit',
    key: 'bearing_replacement_needed',
    destination: _execution,
    honored: true,
  ),

  // ── Ruedas ──────────────────────────────────────────────────────────────
  ServiceQuestionContract(
    family: 'wheels',
    key: 'which_wheel',
    destination: _lineTarget,
    // `both` no divide la línea (queda `none`): `serviceWheelPositions` la
    // lleva a las dos ruedas en la ficha, el diagnóstico y la memoria (paso C).
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'wheel_size',
    destination: _profile,
    profileKey: 'bikes.wheel_size',
    honored: false,
    gap: 'Se lee como dato registrado: si `bikes.wheel_size` se entiende sin '
        'adivinar, se precarga a la vista, no se oculta ni prueba nada para la '
        'matriz. No se escribe: la columna no tiene marca de confirmación, y '
        'llenarla desde una rueda no se distinguiría de confirmarla.',
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'hole_count',
    destination: _profile,
    profileKeyByLocation: _spokeHoles,
    honored: true,
    appliesOnCompletion: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'brake_type',
    destination: _profile,
    profileKey: 'brakeType',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'valve_type',
    destination: _profile,
    profileKey: 'valveType',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'tire_condition',
    destination: _diagnosis,
    diagnosisSystem: 'wheel',
    diagnosisField: 'tireCondition',
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'rim_damage',
    destination: _diagnosis,
    diagnosisSystem: 'wheel',
    diagnosisField: 'rimCondition',
    // «mayor» es aro golpeado, no fisurado: `wheelDiagnosisFindings`.
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'symptom',
    destination: _diagnosis,
    diagnosisSystem: 'wheel',
    diagnosisField: 'hubBearingCondition',
    // Juego y aspereza tienen campo; ruido va a la nota; preventivo no es un
    // hallazgo (`wheelDiagnosisFindings`).
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'rim_tape_condition',
    destination: _execution,
    honored: true,
    upstreamCandidate: 'estado de la cinta de fondo',
    upstreamDecision: UpstreamDecision.visitFinding,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'puncture_cause',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'tire_tubeless_ready',
    destination: _execution,
    honored: true,
    // Park Tool: «tubeless ready» es del neumático (talón cuadrado, carcasa
    // más fuerte) y de la llanta.
    upstreamCandidate: 'tubeless ready del neumático y la llanta instalados',
    upstreamDecision: UpstreamDecision.componentSpec,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'valve_length_mm',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'sealant_volume_ml',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'rim_tape_width_mm',
    destination: _execution,
    honored: true,
    // Sheldon Brown: la cinta tiene el ancho del fondo del aro. El dato es el
    // ancho interno del aro instalado, no la cinta.
    upstreamCandidate: 'ancho interno del aro instalado, por rueda',
    upstreamDecision: UpstreamDecision.componentSpec,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'hub_selected',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'rim_selected',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'spoke_model',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'build_pattern',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'axle_type',
    destination: _profile,
    profileKeyByLocation: _axleInterface,
    // Tipo y diámetro (cierre rápido 9/10 mm, pasante 12/15/20 mm, macizo):
    // lo fija la puntera de cuadro y horquilla, y se confirma con esa rueda
    // (paso F.2). Códigos `catalog_…` del registro `axle_type`, los mismos
    // de horquilla, maza, rueda, cuadro y bici completa.
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'bearing_system',
    destination: _execution,
    honored: true,
    // Park Tool: conos ajustables contra cartucho que se reemplaza entero.
    upstreamCandidate: 'rodamientos de la maza instalada, por rueda',
    upstreamDecision: UpstreamDecision.componentSpec,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'freehub_service_needed',
    destination: _execution,
    honored: true,
  ),
  ServiceQuestionContract(
    family: 'wheels',
    key: 'bearing_replacement_needed',
    destination: _execution,
    honored: true,
  ),
];

/// `brakes` es el alias heredado de `brake` (ver «Hydraulic-Brake Example» y
/// la nota de producción del documento maestro).
String normalizeServiceFamily(String? family) {
  final value = (family ?? '').trim().toLowerCase();
  return value == 'brakes' ? 'brake' : value;
}

final Map<String, ServiceQuestionContract> _contractsByFamilyAndKey = {
  for (final contract in kServiceQuestionContracts)
    '${contract.family}/${contract.key}': contract,
};

ServiceQuestionContract? serviceQuestionContractFor({
  required String? family,
  required String key,
}) {
  return _contractsByFamilyAndKey['${normalizeServiceFamily(family)}/$key'];
}
