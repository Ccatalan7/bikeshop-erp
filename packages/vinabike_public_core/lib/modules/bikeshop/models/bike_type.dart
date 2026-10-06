// Moved from lib/modules/bikeshop/models/bikeshop_models.dart (2026-10-06):
// the HTML store's customer portal names a bike's type with the same words;
// bikeshop_models.dart re-exports it.
enum BikeType {
  road,
  mountain,
  mountainHardtail,
  hybrid,
  electric,
  bmx,
  folding,
  cruiser,
  gravel,
  paseo,
  other;

  String get displayName {
    switch (this) {
      case BikeType.road:
        return 'Ruta';
      case BikeType.mountain:
        return 'MTB doble suspensión';
      case BikeType.mountainHardtail:
        return 'MTB hardtail';
      case BikeType.hybrid:
        return 'Híbrida';
      case BikeType.electric:
        return 'Eléctrica';
      case BikeType.bmx:
        return 'BMX';
      case BikeType.folding:
        return 'Plegable';
      case BikeType.cruiser:
        return 'Cruiser';
      case BikeType.gravel:
        return 'Gravel';
      case BikeType.paseo:
        return 'Paseo / Urbana';
      case BikeType.other:
        return 'Otra';
    }
  }

  String get dbValue {
    switch (this) {
      case BikeType.mountainHardtail:
        return 'mountain_hardtail';
      default:
        return name;
    }
  }

  static BikeType? fromDbValue(String? value) {
    if (value == null || value.isEmpty) return null;

    switch (value) {
      case 'mountain_hardtail':
        return BikeType.mountainHardtail;
      default:
        return BikeType.values.firstWhere(
          (type) => type.name == value,
          orElse: () => BikeType.other,
        );
    }
  }
}
