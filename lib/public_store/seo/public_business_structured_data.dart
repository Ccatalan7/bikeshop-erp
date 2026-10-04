import '../models/public_business_hours.dart';

/// One active row of `online_shipping_rate_tiers`, the table the checkout
/// quotes from (`quote_online_shipping_internal`): an order total from
/// [minOrderGross] (included) up to [maxOrderGross] (excluded, `null` = no
/// limit) pays [shippingGross], delivered in a range of business days.
class PublicShippingTier {
  const PublicShippingTier({
    required this.countryCode,
    required this.minOrderGross,
    required this.maxOrderGross,
    required this.shippingGross,
    required this.minBusinessDays,
    required this.maxBusinessDays,
  });

  factory PublicShippingTier.fromRow(Map<String, dynamic> row) {
    num? number(String key) {
      final value = row[key];
      return value is num ? value : num.tryParse('${value ?? ''}');
    }

    return PublicShippingTier(
      countryCode: '${row['country_code'] ?? ''}'.trim().toUpperCase(),
      minOrderGross: _whole(number('min_order_gross') ?? 0),
      maxOrderGross: switch (number('max_order_gross')) {
        final num value => _whole(value),
        null => null,
      },
      shippingGross: _whole(number('shipping_gross') ?? 0),
      minBusinessDays: number('estimated_min_business_days')?.toInt(),
      maxBusinessDays: number('estimated_max_business_days')?.toInt(),
    );
  }

  final String countryCode;
  final num minOrderGross;
  final num? maxOrderGross;
  final num shippingGross;
  final int? minBusinessDays;
  final int? maxBusinessDays;
}

/// Pesos arrive from PostgREST as `30000.00`; Google reads `30000`.
num _whole(num value) => value % 1 == 0 ? value.toInt() : value;

/// Store-wide facts about how the business sells, added to the business node
/// whose identity (name, legal name, address, contact) `scripts/sync_seo_index.sh`
/// writes from `website_settings`.
///
/// Every value comes from the owner the store already reads: the hours from
/// the ERP's «Horario del local» (the contact page shows the same ones), the
/// shipping from the tiers the checkout charges, the return policy from the
/// published «Política de devoluciones» page, the logo from the one the store
/// paints. Google reads shipping and returns once for the whole business
/// since 2026-09-08, instead of on every product.
Map<String, dynamic> completePublicBusinessStructuredData(
  Map<String, dynamic> identity, {
  required String logoUrl,
  required String imageUrl,
  required String mapUrl,
  required List<PublicBusinessHoursPeriod> hours,
  required List<PublicShippingTier> shippingTiers,
  required String currency,
  required String pickupCountryCode,
  required String returnPolicyUrl,
}) {
  final node = Map<String, dynamic>.from(identity);
  if (logoUrl.isNotEmpty) node['logo'] = logoUrl;
  if (imageUrl.isNotEmpty) node['image'] = imageUrl;
  if (mapUrl.isNotEmpty) node['hasMap'] = mapUrl;

  final openingHours = openingHoursSpecificationFor(hours);
  if (openingHours.isNotEmpty) {
    node['openingHoursSpecification'] = openingHours;
  }

  final services = <Map<String, dynamic>>[
    if (shippingTiers.isNotEmpty)
      {
        '@type': 'ShippingService',
        'name': 'Despacho a domicilio',
        'fulfillmentType': 'https://schema.org/FulfillmentTypeDelivery',
        'shippingConditions': [
          for (final tier in shippingTiers)
            {
              '@type': 'ShippingConditions',
              'shippingDestination': {
                '@type': 'DefinedRegion',
                'addressCountry': tier.countryCode,
              },
              'orderValue': {
                '@type': 'MonetaryAmount',
                'currency': currency,
                'minValue': tier.minOrderGross,
                // Google reads both ends as included; a whole-peso total just
                // under the next tier's start is the last one this tier takes.
                if (tier.maxOrderGross != null)
                  'maxValue': tier.maxOrderGross! - 1,
              },
              'shippingRate': {
                '@type': 'MonetaryAmount',
                'value': tier.shippingGross,
                'currency': currency,
              },
              if (tier.minBusinessDays != null && tier.maxBusinessDays != null)
                'transitTime': {
                  '@type': 'ServicePeriod',
                  'duration': {
                    '@type': 'QuantitativeValue',
                    'minValue': tier.minBusinessDays,
                    'maxValue': tier.maxBusinessDays,
                    'unitCode': 'DAY',
                  },
                  'businessDays': const [
                    'https://schema.org/Monday',
                    'https://schema.org/Tuesday',
                    'https://schema.org/Wednesday',
                    'https://schema.org/Thursday',
                    'https://schema.org/Friday',
                  ],
                },
            },
        ],
      },
    if (pickupCountryCode.isNotEmpty)
      {
        '@type': 'ShippingService',
        'name': 'Retiro en tienda',
        'fulfillmentType': 'https://schema.org/FulfillmentTypeCollectionPoint',
        'shippingConditions': [
          {
            '@type': 'ShippingConditions',
            'shippingDestination': {
              '@type': 'DefinedRegion',
              'addressCountry': pickupCountryCode,
            },
            'shippingRate': {
              '@type': 'MonetaryAmount',
              'value': 0,
              'currency': currency,
            },
          },
        ],
      },
  ];
  if (services.isNotEmpty) node['hasShippingService'] = services;

  // The published page is the policy: its terms (plazo, quién paga, cómo se
  // reembolsa) are written and edited there, so Google gets the link to it
  // and nothing restated beside it.
  if (returnPolicyUrl.isNotEmpty) {
    node['hasMerchantReturnPolicy'] = {
      '@type': 'MerchantReturnPolicy',
      'merchantReturnLink': returnPolicyUrl,
    };
  }
  return node;
}

/// Days that share the same spans become one entry, as Google lists them.
List<Map<String, dynamic>> openingHoursSpecificationFor(
  List<PublicBusinessHoursPeriod> hours,
) {
  const schemaDays = {
    'MONDAY': 'https://schema.org/Monday',
    'TUESDAY': 'https://schema.org/Tuesday',
    'WEDNESDAY': 'https://schema.org/Wednesday',
    'THURSDAY': 'https://schema.org/Thursday',
    'FRIDAY': 'https://schema.org/Friday',
    'SATURDAY': 'https://schema.org/Saturday',
    'SUNDAY': 'https://schema.org/Sunday',
  };
  final daysBySpan = <String, List<String>>{};
  for (final day in publicBusinessDays) {
    for (final period in hours.where((period) => period.day == day)) {
      daysBySpan
          .putIfAbsent('${period.opens}-${period.closes}', () => [])
          .add(schemaDays[day]!);
    }
  }
  return [
    for (final entry in daysBySpan.entries)
      {
        '@type': 'OpeningHoursSpecification',
        'dayOfWeek': entry.value,
        'opens': entry.key.split('-').first,
        'closes': entry.key.split('-').last,
      },
  ];
}
