/// Aro de la bici: una sola lectura para la ficha, los servicios y la matriz.
///
/// `bikes.wheel_size` es texto libre desde siempre. En producción, el
/// 2026-09-27, el mismo aro aparecía escrito como `29"`, `29''` o `29`, y el
/// 700c como `700`, `700c` o `700''`. La ficha ofrece estas etiquetas; el
/// wizard de servicio usa los valores del registro (`v_29`…). Este archivo
/// traduce entre las tres formas y no adivina: lo ambiguo queda sin leer.
library;

/// Etiquetas de la ficha (`bike_form_dialog.dart`, `_wheelSizeOptions`) y el
/// valor del registro que usan las preguntas `wheel_size` de los servicios.
const Map<String, String> kWheelSizeWizardValueByLabel = {
  '12"': 'v_12',
  '16"': 'v_16',
  '20"': 'v_20',
  '24"': 'v_24',
  '26"': 'v_26',
  '27.5"': 'v_27_5',
  '29"': 'v_29',
  '700c': 'v_700c',
  '650b': 'v_650b',
};

final Map<String, String> _labelByWizardValue = {
  for (final entry in kWheelSizeWizardValueByLabel.entries)
    entry.value: entry.key,
};

/// La etiqueta de la ficha que corresponde a lo que la bici tiene escrito, o
/// `null` si no se puede leer sin adivinar.
///
/// Gramática explícita, la misma que `iso_bsd_candidates_for_wheel_size` en
/// el servidor: un número entero o decimal con espacios sólo alrededor y a lo
/// más la pulgada; `650b`; `700`, `700c` o `700"`.
///
/// Casos que quedan sin leer a propósito:
/// - `28`: en Chile se usa para 700c y también para el 28" antiguo (ISO 635).
/// - `27.5" - 26"`: dos aros en un campo; `2 9`: no se juntan dígitos.
/// - medidas que la ficha no ofrece, como `14''`.
String? canonicalBikeWheelSizeLabel(String? raw) {
  if (raw == null) return null;
  final text = raw
      .trim()
      .toLowerCase()
      .replaceAll('”', '"')
      .replaceAll('″', '"')
      .replaceAll("''", '"')
      .replaceAll(',', '.');
  if (RegExp(r'^650\s*b$').hasMatch(text)) return '650b';
  if (RegExp(r'^700\s*(c|")?$').hasMatch(text)) return '700c';

  final number = RegExp(r'^(\d+(?:\.\d+)?)\s*"?$').firstMatch(text);
  if (number == null) return null;
  final label = '${number.group(1)}"';
  return kWheelSizeWizardValueByLabel.containsKey(label) ? label : null;
}

/// Los rótulos de aro que son un solo diámetro de asiento (BSD, ISO 5775) y
/// por eso refutan un neumático de otro: 29″/700c = 622 y 27,5″/650b = 584.
/// La misma tabla que `iso_bsd_candidates_for_wheel_size` en el servidor
/// (20260928110000). Los demás no refutan: 26″ son al menos seis diámetros
/// (559, 571, 584 —el 650B se vendió como «26 × 1 1/2»—, 590, 597 y 599) y
/// 24″, 20″, 16″ y 14″ tampoco tienen un conjunto que se pueda dar por
/// completo (Sheldon Brown, «Tire Sizing»; la primera versión refutaba con
/// listas incompletas, revisión de Codex del 2026-09-28).
///
/// La matriz de compatibilidad tiene su propia lectura: ella sugiere lo
/// probable; ésta sólo refuta lo imposible.
const Map<String, Set<int>> kIsoBsdCandidatesByWheelLabel = {
  '27.5"': {584},
  '29"': {622},
  '700c': {622},
  '650b': {584},
};

/// El BSD que exige el aro escrito en la bici; vacío si el rótulo no es un
/// solo diámetro o no se lee sin adivinar (`26"`, `28`, `27.5" - 26"`):
/// lo vacío no refuta nada.
Set<int> isoBsdCandidatesForBikeWheelSize(String? raw) =>
    kIsoBsdCandidatesByWheelLabel[canonicalBikeWheelSizeLabel(raw)] ?? const {};

// Los BSD de la tabla ISO de Sheldon Brown («Tire Sizing») entre 150 y 700
// mm, con el nombre que usa el taller; el mismo texto que
// `iso_bsd_wheel_label` en el servidor.
const Map<int, String> _isoBsdWheelName = {
  686: '32″',
  642: '28″ 700A',
  635: '28″ 635',
  630: '27″',
  622: '29″/700c',
  609: '27″ danés',
  599: '26″ 599',
  597: '26″ inglés',
  590: '26″ 650a',
  584: '27,5″/650b',
  583: '700D',
  571: '26″ 650c',
  559: '26″',
  547: '24″ 547',
  541: '24″ 600A',
  540: '24″ 540',
  534: '24″ holandés',
  520: '24″ 520',
  507: '24″',
  501: '22″ inglés',
  490: '22″ 550A',
  489: '22″ holandés',
  484: '22″ 550B',
  457: '22″',
  451: '20″ 451',
  440: '20″ 500A',
  438: '20″ holandés',
  428: '20″ sueco',
  419: '20″ 419',
  406: '20″',
  400: '18″ 400',
  390: '18″ 450A',
  369: '17″',
  355: '18″',
  349: '16″ 349',
  340: '16″ 400A',
  337: '16″ 337',
  335: '16″ 335',
  317: '16″ 317',
  305: '16″',
  298: '14″ 298',
  288: '14″ 350A',
  254: '14″',
  252: '12″ francés',
  203: '12″',
  152: '10″',
};

/// Los BSD que ofrece la ficha de la bici: primero los tres del taller
/// (29″, 27,5″ y 26″) y después el resto, del más grande al más chico. Una
/// lista `const`, no derivada del mapa: una recarga en caliente no vuelve a
/// calcular un `final` global ya calculado (2026-09-28).
const List<int> kIsoWheelBsdOptions = [
  // Los tres del taller.
  622, 584, 559,
  // El resto, del más grande al más chico.
  686,
  642,
  635,
  630,
  609,
  599,
  597,
  590,
  583,
  571,
  547,
  541,
  540,
  534,
  520,
  507,
  501,
  490,
  489,
  484,
  457,
  451,
  440,
  438,
  428,
  419,
  406,
  400,
  390,
  369,
  355,
  349,
  340,
  337,
  335,
  317,
  305,
  298,
  288,
  254,
  252,
  203,
  152,
];

/// «622 (29″/700c)»: un BSD como lo dice el taller (el mismo texto que
/// `iso_bsd_wheel_label` en el servidor).
String isoWheelBsdLabel(int bsd) {
  final name = _isoBsdWheelName[bsd];
  return name == null ? '$bsd' : '$bsd ($name)';
}

/// El BSD de cada rueda en la ficha de la bici (20260928110000).
const Map<String, String> kWheelBsdFactKeyByPosition = {
  'front': 'frontWheelBsdMm',
  'rear': 'rearWheelBsdMm',
};

/// El valor del registro para una etiqueta de la ficha, o `null`.
String? wheelSizeWizardValueForLabel(String? label) =>
    label == null ? null : kWheelSizeWizardValueByLabel[label];

/// La etiqueta de la ficha para un valor del registro (`v_29` → `29"`).
String? wheelSizeLabelForWizardValue(String? value) =>
    value == null ? null : _labelByWizardValue[value];

/// Eje de cada rueda (`frontAxleInterface` / `rearAxleInterface`, paso F.2):
/// los códigos del registro `axle_type`, que comparten horquilla, maza,
/// rueda, cuadro y bici completa (`front_axle_type`, `rear_axle_type`), con
/// sus etiquetas. El read-back de `20260928030000` prueba que son
/// exactamente los activos del registro.
const Map<String, String> kAxleInterfaceLabels = {
  'catalog_70d7fea9eaec337320d0814e6a8e7836': 'Cierre rápido 9 mm (delantero)',
  'catalog_8a246b8f84c98b2fda1d402e902355a4': 'Cierre rápido 10 mm (trasero)',
  'catalog_04c89a1828095f03f3c390c821f8bccd': 'Eje pasante 12 mm',
  'catalog_d2128659275dc69ee5e50dc9500992fa': 'Eje pasante 15 mm',
  'catalog_855ee050fed24e28691a34b52fb4105e': 'Eje pasante 20 mm',
  'catalog_4e5d230b5cd1c062e5addf17bb19909a':
      'Eje macizo con tuercas 3/8" (9,5 mm)',
  'catalog_e574e4ca8fa443b057c9d2595063c918':
      'Eje macizo con tuercas 5/16" (8 mm)',
  'catalog_cd4327044ca6b8f574153f9ba85d39fc': 'Eje macizo con tuercas M10',
};

/// «Desconocido / sin confirmar» del registro: se puede guardar como
/// revisado, pero no es un dato de la bici y nunca se confirma.
const String kRegistryUnknownCode = 'catalog_de6e897b1c6ced32e6762f3ceaebffd6';

/// El eje en palabras de taller, o `null` si no es un eje conocido.
String? axleInterfaceLabel(Object? code) => kAxleInterfaceLabels['$code'];
