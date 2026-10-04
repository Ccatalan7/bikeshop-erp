import '../models/public_business_hours.dart';

/// Store-wide facts about the business, added to the node whose identity
/// (name, legal name, address, contact) `scripts/sync_seo_index.sh` writes
/// from `website_settings`.
///
/// Every value comes from the owner the store already reads: the hours from
/// the ERP's «Horario del local» (the contact page shows the same ones), the
/// return policy from the published «Política de devoluciones» page, the logo
/// from the one the store paints.
///
/// Shipping is deliberately not declared (2026-10-04). The store ships to
/// «Chile continental», and Google Search documents no way to leave Easter
/// Island and Juan Fernández out of Chile: its `DefinedRegion` reads regions
/// only for the US, Australia and Japan and postal codes only for Australia,
/// Canada and the US (schema.org itself could list postal ranges; Google
/// would not read them). `addressCountry: CL` would promise delivery the
/// shipping page denies, on a Merchant account suspended for misleading
/// information. `google_merchant_identity_contract_test.dart` keeps it out
/// until there is a way to say it exactly.
Map<String, dynamic> completePublicBusinessStructuredData(
  Map<String, dynamic> identity, {
  required String logoUrl,
  required String imageUrl,
  required String mapUrl,
  required List<PublicBusinessHoursPeriod> hours,
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
