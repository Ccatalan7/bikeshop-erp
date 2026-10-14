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
    if (zone.regionCodes.isEmpty) {
      return 'Elige al menos una región para «$name».';
    }
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

/// A zone the suggestion proposes: its regions, its price relative to
/// Santiago and its delivery window. Ratios from a carrier's public
/// reference rates by destination (Blue Express, 0,5–3 kg, read 2026-10-14):
/// same region 3.650, Santiago 4.500, Coquimbo–Maule up to 5.300, the south
/// up to 6.100, the north up to 8.300 and the far south 9.500. Each zone
/// takes its most expensive region, so no destination is charged below
/// cost. The shop ships from Viña del Mar.
typedef SuggestedZone = ({
  String name,
  List<String> regions,
  double factor,
  int minDays,
  int maxDays,
});

const List<SuggestedZone> suggestedZoneLayout = [
  (
    name: 'Región de Valparaíso',
    regions: ['CL-VS'],
    factor: 0.81,
    minDays: 1,
    maxDays: 3,
  ),
  (
    name: 'Santiago',
    regions: ['CL-RM'],
    factor: 1,
    minDays: 2,
    maxDays: 4,
  ),
  (
    name: 'Centro',
    regions: ['CL-CO', 'CL-LI', 'CL-ML'],
    factor: 1.18,
    minDays: 2,
    maxDays: 5,
  ),
  (
    name: 'Sur',
    regions: ['CL-NB', 'CL-BI', 'CL-AR', 'CL-LR', 'CL-LL'],
    factor: 1.36,
    minDays: 3,
    maxDays: 6,
  ),
  (
    name: 'Norte',
    regions: ['CL-AT', 'CL-AN', 'CL-TA', 'CL-AP'],
    factor: 1.84,
    minDays: 3,
    maxDays: 7,
  ),
  (
    name: 'Zona austral',
    regions: ['CL-AI', 'CL-MA'],
    factor: 2.11,
    minDays: 5,
    maxDays: 10,
  ),
];

/// The purchase bands, standing in for the package's size, and what each
/// costs relative to the smallest (the same carrier: 3.650, 4.700, 5.700 and
/// 7.600 for the four sizes to one destination).
const List<({int from, double factor})> suggestedBandLayout = [
  (from: 0, factor: 1),
  (from: 30000, factor: 1.29),
  (from: 80000, factor: 1.56),
  (from: 150000, factor: 2.08),
];

/// A price the way shops write them, never below [value]: 7.426 → 7.490.
int roundUpShippingPrice(double value) =>
    (((value + 10) / 500).ceil() * 500) - 10;

/// Zones and bands from what the carrier charges for a small package to
/// Santiago. With a boleta its IVA is no credit, so the customer's price
/// must leave that whole cost after the sale's own IVA (×1,19): with
/// $6.240 at the counter, Santiago's smallest band is $7.490 (2026-10-14:
/// WEB-26-00021 charged $6.990 and lost $366).
List<ShippingZone> suggestedShippingZones({
  required int carrierCostToSantiago,
  required bool paidWithReceipt,
}) {
  final base = carrierCostToSantiago * (paidWithReceipt ? 1.19 : 1.0);
  return [
    for (final zone in suggestedZoneLayout)
      ShippingZone(
        name: zone.name,
        regionCodes: zone.regions,
        bands: [
          for (final (index, band) in suggestedBandLayout.indexed)
            ShippingBand(
              minOrderGross: band.from,
              maxOrderGross: index + 1 < suggestedBandLayout.length
                  ? suggestedBandLayout[index + 1].from
                  : null,
              shippingGross:
                  roundUpShippingPrice(base * zone.factor * band.factor),
              minDays: zone.minDays,
              maxDays: zone.maxDays,
            ),
        ],
      ),
  ];
}
