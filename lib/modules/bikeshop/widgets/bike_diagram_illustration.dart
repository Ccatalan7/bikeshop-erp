import 'package:flutter/material.dart';

import '../models/bikeshop_models.dart';

enum BikeDiagramVariant {
  mountainFullSuspension,
  mountainHardtail,
  road,
  gravel,
  commuter,
  fixie,
  bmx,
  electric,
}

extension BikeDiagramVariantX on BikeDiagramVariant {
  String get displayName {
    switch (this) {
      case BikeDiagramVariant.mountainFullSuspension:
        return 'MTB doble suspensión';
      case BikeDiagramVariant.mountainHardtail:
        return 'MTB hardtail';
      case BikeDiagramVariant.road:
        return 'Ruta';
      case BikeDiagramVariant.gravel:
        return 'Gravel / all-road';
      case BikeDiagramVariant.commuter:
        return 'Commuter / touring';
      case BikeDiagramVariant.fixie:
        return 'Fixie / track';
      case BikeDiagramVariant.bmx:
        return 'BMX';
      case BikeDiagramVariant.electric:
        return 'Eléctrica';
    }
  }
}

class BikeDiagramPinPlacement {
  final Offset position;
  final bool labelRight;

  const BikeDiagramPinPlacement({
    required this.position,
    required this.labelRight,
  });
}

class _BikeDiagramAssetSpec {
  final String assetPath;
  final bool flipX;
  final EdgeInsets padding;

  const _BikeDiagramAssetSpec({
    required this.assetPath,
    this.flipX = false,
    this.padding = EdgeInsets.zero,
  });
}

BikeDiagramVariant resolveBikeDiagramVariant({
  required Bike? bike,
}) {
  switch (bike?.bikeType) {
    case BikeType.mountain:
      return BikeDiagramVariant.mountainFullSuspension;
    case BikeType.mountainHardtail:
      return BikeDiagramVariant.mountainHardtail;
    case BikeType.road:
      return BikeDiagramVariant.road;
    case BikeType.gravel:
      return BikeDiagramVariant.gravel;
    case BikeType.bmx:
      return BikeDiagramVariant.bmx;
    case BikeType.electric:
      return BikeDiagramVariant.electric;
    case BikeType.hybrid:
    case BikeType.folding:
    case BikeType.cruiser:
      return BikeDiagramVariant.commuter;
    case BikeType.other:
    case null:
      return BikeDiagramVariant.fixie;
  }
}

BikeDiagramPinPlacement? resolveBikeDiagramPinPlacement({
  required BikeDiagramVariant variant,
  required String systemKey,
}) {
  final placements = switch (variant) {
    BikeDiagramVariant.mountainFullSuspension => _fullSuspensionPlacements,
    BikeDiagramVariant.mountainHardtail => _hardtailPlacements,
    BikeDiagramVariant.road => _roadPlacements,
    BikeDiagramVariant.gravel => _roadPlacements,
    BikeDiagramVariant.fixie => _roadPlacements,
    BikeDiagramVariant.commuter => _commuterPlacements,
    BikeDiagramVariant.electric => _commuterPlacements,
    BikeDiagramVariant.bmx => _bmxPlacements,
  };
  return placements[systemKey];
}

const Map<BikeDiagramVariant, _BikeDiagramAssetSpec> _variantAssets = {
  BikeDiagramVariant.mountainFullSuspension: _BikeDiagramAssetSpec(
    assetPath: 'assets/images/mtb_diagnostic_bg.png',
    padding: EdgeInsets.fromLTRB(12, 12, 12, 18),
  ),
  BikeDiagramVariant.mountainHardtail: _BikeDiagramAssetSpec(
    assetPath: 'assets/icons/mtb_bike_v2.png',
    flipX: true,
    padding: EdgeInsets.all(22),
  ),
  BikeDiagramVariant.road: _BikeDiagramAssetSpec(
    assetPath: 'assets/images/wireframe_bike.png',
    padding: EdgeInsets.all(10),
  ),
  BikeDiagramVariant.gravel: _BikeDiagramAssetSpec(
    assetPath: 'assets/images/wireframe_bike.png',
    padding: EdgeInsets.all(10),
  ),
  BikeDiagramVariant.commuter: _BikeDiagramAssetSpec(
    assetPath: 'assets/images/wireframe_bike.png',
    padding: EdgeInsets.all(10),
  ),
  BikeDiagramVariant.fixie: _BikeDiagramAssetSpec(
    assetPath: 'assets/images/wireframe_bike.png',
    padding: EdgeInsets.all(10),
  ),
  BikeDiagramVariant.bmx: _BikeDiagramAssetSpec(
    assetPath: 'assets/images/wireframe_bike.png',
    padding: EdgeInsets.all(14),
  ),
  BikeDiagramVariant.electric: _BikeDiagramAssetSpec(
    assetPath: 'assets/images/wireframe_bike.png',
    padding: EdgeInsets.all(10),
  ),
};

const Map<String, BikeDiagramPinPlacement> _fullSuspensionPlacements = {
  'cockpit': BikeDiagramPinPlacement(
    position: Offset(0.65, 0.22),
    labelRight: true,
  ),
  'suspension': BikeDiagramPinPlacement(
    position: Offset(0.72, 0.38),
    labelRight: true,
  ),
  'front_brake': BikeDiagramPinPlacement(
    position: Offset(0.81, 0.55),
    labelRight: true,
  ),
  'wheels': BikeDiagramPinPlacement(
    position: Offset(0.73, 0.68),
    labelRight: true,
  ),
  'drivetrain': BikeDiagramPinPlacement(
    position: Offset(0.39, 0.56),
    labelRight: false,
  ),
  'rear_brake': BikeDiagramPinPlacement(
    position: Offset(0.22, 0.62),
    labelRight: false,
  ),
};

const Map<String, BikeDiagramPinPlacement> _hardtailPlacements = {
  'cockpit': BikeDiagramPinPlacement(
    position: Offset(0.69, 0.25),
    labelRight: true,
  ),
  'suspension': BikeDiagramPinPlacement(
    position: Offset(0.65, 0.40),
    labelRight: true,
  ),
  'front_brake': BikeDiagramPinPlacement(
    position: Offset(0.79, 0.58),
    labelRight: true,
  ),
  'wheels': BikeDiagramPinPlacement(
    position: Offset(0.71, 0.72),
    labelRight: true,
  ),
  'drivetrain': BikeDiagramPinPlacement(
    position: Offset(0.47, 0.57),
    labelRight: false,
  ),
  'rear_brake': BikeDiagramPinPlacement(
    position: Offset(0.24, 0.63),
    labelRight: false,
  ),
};

const Map<String, BikeDiagramPinPlacement> _roadPlacements = {
  'cockpit': BikeDiagramPinPlacement(
    position: Offset(0.73, 0.21),
    labelRight: true,
  ),
  'front_brake': BikeDiagramPinPlacement(
    position: Offset(0.81, 0.59),
    labelRight: true,
  ),
  'wheels': BikeDiagramPinPlacement(
    position: Offset(0.72, 0.73),
    labelRight: true,
  ),
  'drivetrain': BikeDiagramPinPlacement(
    position: Offset(0.46, 0.61),
    labelRight: false,
  ),
  'rear_brake': BikeDiagramPinPlacement(
    position: Offset(0.22, 0.67),
    labelRight: false,
  ),
};

const Map<String, BikeDiagramPinPlacement> _commuterPlacements = {
  'cockpit': BikeDiagramPinPlacement(
    position: Offset(0.71, 0.24),
    labelRight: true,
  ),
  'front_brake': BikeDiagramPinPlacement(
    position: Offset(0.81, 0.60),
    labelRight: true,
  ),
  'wheels': BikeDiagramPinPlacement(
    position: Offset(0.71, 0.74),
    labelRight: true,
  ),
  'drivetrain': BikeDiagramPinPlacement(
    position: Offset(0.45, 0.63),
    labelRight: false,
  ),
  'rear_brake': BikeDiagramPinPlacement(
    position: Offset(0.22, 0.68),
    labelRight: false,
  ),
};

const Map<String, BikeDiagramPinPlacement> _bmxPlacements = {
  'cockpit': BikeDiagramPinPlacement(
    position: Offset(0.67, 0.26),
    labelRight: true,
  ),
  'front_brake': BikeDiagramPinPlacement(
    position: Offset(0.78, 0.62),
    labelRight: true,
  ),
  'wheels': BikeDiagramPinPlacement(
    position: Offset(0.69, 0.76),
    labelRight: true,
  ),
  'drivetrain': BikeDiagramPinPlacement(
    position: Offset(0.47, 0.63),
    labelRight: false,
  ),
  'rear_brake': BikeDiagramPinPlacement(
    position: Offset(0.27, 0.69),
    labelRight: false,
  ),
};

class BikeDiagramIllustration extends StatelessWidget {
  final BikeDiagramVariant variant;

  const BikeDiagramIllustration({
    super.key,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final spec = _variantAssets[variant]!;

    Widget child = Padding(
      padding: spec.padding,
      child: Image.asset(
        spec.assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );

    if (spec.flipX) {
      child = Transform.flip(
        flipX: true,
        child: child,
      );
    }

    return SizedBox.expand(child: child);
  }
}
