/// Dirección y cockpit de la ficha de la bici: los mismos conceptos que el
/// inventario (`steerer_fit`, `headset_upper_shis`, `bar_clamp_diameter_mm`,
/// `grip_area_diameter_mm`, `handlebar_clamp_mm`, `seatpost_diameter_mm`,
/// `seatpost_kind`), para que la bici y el producto se comparen sin traducir
/// (20261002170000; wiki `direccion.md` y `manubrio-potencia-y-tija.md`).
library;

import '../models/bikeshop_models.dart';

/// Las claves de la sección 6 de la hoja, en su orden.
const String kSteererFitKey = 'steererFit';
const String kHeadsetUpperShisKey = 'headsetUpperShis';
const String kHeadsetLowerShisKey = 'headsetLowerShis';
const String kHandlebarClampKey = 'handlebarClampMm';
const String kControlsBarDiameterKey = 'controlsBarDiameterMm';
const String kSeatpostDiameterKey = 'seatpostDiameterMm';
const String kSeatpostKindKey = 'seatpostKind';

/// El tubo de la horquilla. Los códigos son los de la puerta de la ficha
/// (`patch_bike_technical_facts_v1`); `steerer_fit` del inventario se lee
/// con el mapa de su fila.
const Map<String, String> kSteererFitLabels = {
  'straight_1_1_8': '1⅛″ (28,6 mm)',
  'tapered_1_1_8_1_5': 'Cónico 1⅛″–1,5″',
  'straight_1': '1″ (25,4 mm)',
  'straight_1_1_4': '1¼″ (31,8 mm)',
  'straight_1_5': '1,5″ (38,1 mm)',
};

/// El diámetro de arriba del tubo, el que aprieta la potencia: un tubo
/// cónico es de 1⅛″ arriba.
const Map<String, double> kSteererTopDiameterMm = {
  'straight_1': 25.4,
  'straight_1_1_8': 28.6,
  'straight_1_1_4': 31.8,
  'straight_1_5': 38.1,
  'tapered_1_1_8_1_5': 28.6,
};

/// Los códigos SHIS que más se ven (Park Tool). La dirección se elige por
/// separado arriba y abajo; un código que no está igual se conserva.
const List<String> kHeadsetUpperShisOptions = [
  'ZS44/28.6',
  'EC34/28.6',
  'IS41/28.6',
  'IS42/28.6',
  'ZS49/28.6',
  'EC44/28.6',
  'IS52/28.6',
];
const List<String> kHeadsetLowerShisOptions = [
  'ZS56/40',
  'EC44/40',
  'IS52/40',
  'EC49/40',
  'ZS44/30',
  'EC34/30',
  'IS41/30',
  'IS42/30',
  'ZS56/30',
];

/// La abrazadera del manubrio, la de la potencia.
const List<double> kHandlebarClampOptions = [22.2, 25.4, 26.0, 31.8, 35.0];

/// La zona de mandos: plano o de ruta.
const List<double> kControlsBarDiameterOptions = [22.2, 23.8];

/// Para qué manubrio es cada zona de mandos, por su medida escrita.
const Map<String, String> kControlsBarDiameterContext = {
  '22.2': 'plano: MTB, paseo, BMX',
  '23.8': 'ruta (drop)',
};

/// Los diámetros de tija que más se ven.
const List<double> kSeatpostDiameterOptions = [
  25.4,
  26.8,
  27.2,
  30.9,
  31.6,
  34.9,
];

const Map<String, String> kSeatpostKindLabels = {
  'rigid': 'Rígida',
  'suspension': 'Con suspensión',
  'dropper': 'Telescópica',
};

/// «22,2 mm»: la medida con coma decimal.
String cockpitMillimeters(num value) {
  final text = value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();
  return '${text.replaceAll('.', ',')} mm';
}

/// La zona de mandos que dice el tipo de bici: un manubrio de ruta (ruta y
/// gravel) es de 23,8 ahí; uno plano, de 22,2. Es una sugerencia sin
/// confirmar, como la suspensión que fija el tipo: no se guarda sola.
double? suggestedControlsBarDiameterForBikeType(BikeType? type) =>
    switch (type) {
      BikeType.road || BikeType.gravel => 23.8,
      BikeType.mountain ||
      BikeType.mountainHardtail ||
      BikeType.hybrid ||
      BikeType.bmx ||
      BikeType.folding ||
      BikeType.cruiser ||
      BikeType.paseo =>
        22.2,
      _ => null,
    };
