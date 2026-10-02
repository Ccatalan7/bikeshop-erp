/// Las opciones de la ficha técnica de la bici que no tienen otro dueño.
///
/// Las usan el formulario de la bici (`bike_form_dialog.dart`) y la hoja que
/// se edita en su lugar (`bike_spec_draft.dart`): una sola lista, para que
/// las dos no ofrezcan valores distintos para el mismo dato. Frenos, ruedas,
/// pedalier y transmisión tienen sus catálogos en sus propios archivos de
/// `config/`.
library;

import '../models/bikeshop_models.dart';
import 'brake_canonical_data.dart';
import 'wheel_canonical_data.dart';

const Map<String, String> kBikeSuspensionLayoutOptions = {
  'rigid': 'Rígida',
  'front_suspension': 'Suspensión delantera',
  'full_suspension': 'Doble suspensión',
  'unknown': 'Desconocido',
};

/// Las suspensiones posibles con el tipo de bici; `null` si el tipo no
/// limita. Una hardtail no es doble suspensión y una BMX es rígida.
const List<String> kHardtailSuspensionLayouts = ['front_suspension', 'rigid'];
const List<String> kBmxSuspensionLayouts = ['rigid'];

List<String>? allowedSuspensionLayoutsForBikeType(BikeType? type) =>
    switch (type) {
      BikeType.mountainHardtail => kHardtailSuspensionLayouts,
      BikeType.bmx => kBmxSuspensionLayouts,
      _ => null,
    };

/// El eje de cada rueda con «Desconocido / sin confirmar» del registro, que
/// se guarda como revisado y nunca como confirmado.
const Map<String, String> kBikeAxleInterfaceOptions = {
  ...kAxleInterfaceLabels,
  kRegistryUnknownCode: 'Desconocido / sin confirmar',
};

/// El anclaje del rotor con «Desconocido»: revisado, nunca confirmado, y no
/// refuta ningún rotor.
const Map<String, String> kBikeRotorMountChoiceOptions = {
  ...kBikeRotorMountOptions,
  'unknown': 'Desconocido',
};

const Map<String, String> kBikeValveTypeOptions = {
  'presta': 'Presta',
  'schrader': 'Schrader',
  'dunlop': 'Dunlop',
  'other': 'Otra',
  'unknown': 'Desconocido',
};

const List<String> kBikeFrameSizeOptions = [
  'XXS',
  'XS',
  'S',
  'M',
  'L',
  'XL',
  'XXL',
  '48cm',
  '50cm',
  '52cm',
  '54cm',
  '56cm',
  '58cm',
  '60cm',
  'Otra'
];

const List<String> kBikeWheelSizeOptions = [
  '12"',
  '16"',
  '20"',
  '24"',
  '26"',
  '27.5"',
  '29"',
  '700c',
  '650b',
  'Otra'
];

const List<int> kBikeRotorSizeOptions = [140, 160, 180, 203, 220];
const List<int> kBikeFrontChainringCountOptions = [1, 2, 3];
const List<int> kBikeRearCogCountOptions = [
  1,
  3,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14
];
const List<int> kBikeFrontHubSpacingOptions = [74, 100, 110, 135, 150];
const List<int> kBikeRearHubSpacingOptions = [
  110,
  120,
  126,
  130,
  135,
  142,
  148,
  150,
  157,
  170,
  177,
  190,
  197,
];
const List<int> kBikeSpokeHoleOptions = [20, 24, 28, 32, 36, 40, 48];
