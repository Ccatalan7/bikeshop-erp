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
/// Casos que quedan sin leer a propósito:
/// - `28`: en Chile se usa para 700c y también para el 28" antiguo (ISO 635).
/// - `27.5" - 26"`: dos aros en un campo.
/// - medidas que la ficha no ofrece, como `14''`.
String? canonicalBikeWheelSizeLabel(String? raw) {
  if (raw == null) return null;
  final text = raw
      .trim()
      .toLowerCase()
      .replaceAll('”', '"')
      .replaceAll('″', '"')
      .replaceAll("''", '"')
      .replaceAll(',', '.')
      .replaceAll(' ', '');
  if (text.isEmpty) return null;

  final number = RegExp(r'\d+(\.\d+)?').allMatches(text).toList();
  if (number.length != 1) return null;

  if (text == '650b') return '650b';
  if (text == '700' || text == '700c' || text == '700"') return '700c';

  final unit = text.replaceFirst(number.single.group(0)!, '');
  if (unit.isNotEmpty && unit != '"') return null;

  final label = '${number.single.group(0)}"';
  return kWheelSizeWizardValueByLabel.containsKey(label) ? label : null;
}

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
