/// A Chilean region as the shipping zones name it (ISO 3166-2:CL), north to
/// south. The database owns the same list (`online_shipping_region_codes`).
typedef ShippingRegion = ({String code, String name});

const List<ShippingRegion> chileanShippingRegions = [
  (code: 'CL-AP', name: 'Arica y Parinacota'),
  (code: 'CL-TA', name: 'Tarapacá'),
  (code: 'CL-AN', name: 'Antofagasta'),
  (code: 'CL-AT', name: 'Atacama'),
  (code: 'CL-CO', name: 'Coquimbo'),
  (code: 'CL-VS', name: 'Valparaíso'),
  (code: 'CL-RM', name: 'Metropolitana'),
  (code: 'CL-LI', name: "O'Higgins"),
  (code: 'CL-ML', name: 'Maule'),
  (code: 'CL-NB', name: 'Ñuble'),
  (code: 'CL-BI', name: 'Biobío'),
  (code: 'CL-AR', name: 'La Araucanía'),
  (code: 'CL-LR', name: 'Los Ríos'),
  (code: 'CL-LL', name: 'Los Lagos'),
  (code: 'CL-AI', name: 'Aysén'),
  (code: 'CL-MA', name: 'Magallanes'),
];

String shippingRegionName(String code) =>
    chileanShippingRegions
        .where((region) => region.code == code)
        .firstOrNull
        ?.name ??
    code;

/// One price of a zone: purchases from [minOrderGross] up to (not
/// including) [maxOrderGross] pay [shippingGross]; the last band has no cap.
/// The subtotal stands for the package's size: the catalog has no weights.
class ShippingBand {
  const ShippingBand({
    required this.minOrderGross,
    required this.shippingGross,
    this.maxOrderGross,
    this.minDays = 3,
    this.maxDays = 7,
  });

  final int minOrderGross;
  final int? maxOrderGross;
  final int shippingGross;
  final int minDays;
  final int maxDays;

  factory ShippingBand.fromJson(Map<String, dynamic> json) {
    int whole(Object? value) =>
        value is num ? value.round() : num.tryParse('$value')?.round() ?? 0;
    final max = json['max_order_gross'];
    return ShippingBand(
      minOrderGross: whole(json['min_order_gross']),
      maxOrderGross: max == null ? null : whole(max),
      shippingGross: whole(json['shipping_gross']),
      minDays: whole(json['estimated_min_business_days']),
      maxDays: whole(json['estimated_max_business_days']),
    );
  }

  Map<String, dynamic> toJson() => {
        'min_order_gross': minOrderGross,
        'max_order_gross': maxOrderGross,
        'shipping_gross': shippingGross,
        'estimated_min_business_days': minDays,
        'estimated_max_business_days': maxDays,
      };
}

/// A zone of the store's shipping: a name, its regions and its bands.
class ShippingZone {
  const ShippingZone({
    required this.name,
    required this.regionCodes,
    required this.bands,
  });

  final String name;
  final List<String> regionCodes;
  final List<ShippingBand> bands;

  factory ShippingZone.fromJson(Map<String, dynamic> json) {
    final regions = json['region_codes'];
    final tiers = json['tiers'];
    return ShippingZone(
      name: json['name']?.toString() ?? '',
      regionCodes: [
        if (regions is List) ...regions.map((code) => code.toString()),
      ],
      bands: [
        if (tiers is List)
          for (final tier in tiers.whereType<Map>())
            ShippingBand.fromJson(Map<String, dynamic>.from(tier)),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'region_codes': regionCodes,
        'tiers': [for (final band in bands) band.toJson()],
      };
}

/// What is wrong with the zones before saving, in the operator's words; null
/// when they can be saved. The database checks the same and has the last
/// word (`save_online_shipping_zones`).
String? shippingZonesProblem(List<ShippingZone> zones) {
  if (zones.isEmpty) return 'Agrega al menos una zona.';
  final seen = <String, String>{};
  for (final (index, zone) in zones.indexed) {
    final name = zone.name.trim();
    if (name.isEmpty) return 'La zona ${index + 1} necesita un nombre.';
    if (zone.regionCodes.isEmpty)
      return 'Elige al menos una región para «$name».';
    for (final code in zone.regionCodes) {
      final other = seen[code];
      if (other != null) {
        return '${shippingRegionName(code)} está en «$other» y en «$name».';
      }
      seen[code] = name;
    }
    if (zone.bands.isEmpty) return '«$name» necesita al menos una tarifa.';
    var start = 0;
    for (final (bandIndex, band) in zone.bands.indexed) {
      final last = bandIndex == zone.bands.length - 1;
      if (band.minOrderGross != start) {
        return 'Los tramos de «$name» deben seguirse sin huecos desde \$0.';
      }
      if (!last && (band.maxOrderGross ?? 0) <= band.minOrderGross) {
        return 'Cada tramo de «$name» debe terminar después de donde empieza.';
      }
      if (band.shippingGross < 0) return 'Revisa los precios de «$name».';
      if (band.minDays < 0 ||
          band.maxDays < band.minDays ||
          band.maxDays > 60) {
        return 'Revisa los días de entrega de «$name».';
      }
      start = band.maxOrderGross ?? start;
    }
  }
  return null;
}
