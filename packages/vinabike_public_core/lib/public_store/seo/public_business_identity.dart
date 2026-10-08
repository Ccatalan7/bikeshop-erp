/// The business node's identity (name, legal name, contact, address), from
/// the public settings.
///
/// `scripts/sync_seo_index.sh` writes the same node into the Flutter store's
/// `index.html` with jq; the HTML storefront builds it here, with the same
/// keys, fallbacks and address cleanup, and completes it with
/// `completePublicBusinessStructuredData` like the SEO generator does. The
/// parity check of phase 1 compares both nodes on the live site.
library;

String _setting(Map<String, String> settings, String key, String fallback) {
  final value = settings[key]?.trim() ?? '';
  return value.isEmpty ? fallback : value;
}

const _ascii = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
  'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N',
};

String _transliterate(String value) {
  final buffer = StringBuffer();
  for (final char in value.split('')) {
    buffer.write(_ascii[char] ?? char);
  }
  return buffer.toString();
}

String _trimCommas(String value) =>
    value.replaceAll(RegExp(r'^[\s,]+'), '').replaceAll(RegExp(r'[\s,]+$'), '');

/// The country as one clean token: commas and a doubled word removed.
String normalizePublicAddressCountry(String raw) {
  var country = _trimCommas(raw);
  if (country.contains(',')) {
    country = _trimCommas(country.split(',').first);
  }
  final doubled = RegExp(r'^(\S+)\s+\1$', caseSensitive: false)
      .firstMatch(country);
  return doubled == null ? country : doubled.group(1)!;
}

/// The street without a trailing `, country` or `, city` already
/// written into it.
String normalizePublicStreetAddress(
  String street,
  String city,
  String country,
) {
  var clean = street;
  for (final value in {country, _transliterate(country)}) {
    if (value.isEmpty) continue;
    clean = clean.replaceAll(
      RegExp(',\\s*${RegExp.escape(value)}\\s*\$', caseSensitive: false),
      '',
    );
  }
  for (final value in {city, _transliterate(city)}) {
    if (value.isEmpty) continue;
    clean = clean.replaceAll(
      RegExp(',\\s*${RegExp.escape(value)}\\s*\$', caseSensitive: false),
      '',
    );
  }
  return clean.replaceAll(RegExp(r'[\s,]+$'), '');
}

/// The `BikeStore` identity node, as `sync_seo_index.sh` builds it.
Map<String, dynamic> buildPublicBusinessIdentity(Map<String, String> settings) {
  final name = _setting(
    settings,
    'seo_business_name',
    _setting(settings, 'store_name', ''),
  );
  final legalName = _setting(settings, 'business_legal_name', '');
  final taxId = _setting(settings, 'business_tax_id', '');
  final phone = _setting(
    settings,
    'seo_phone',
    _setting(settings, 'contact_phone', ''),
  );
  final email = _setting(
    settings,
    'seo_email',
    _setting(settings, 'contact_email', ''),
  );
  final streetRaw = _setting(
    settings,
    'seo_address_street',
    _setting(settings, 'contact_address', ''),
  );
  final city = _setting(
    settings,
    'seo_address_city',
    _setting(settings, 'seo_address_locality', ''),
  );
  final region = _setting(settings, 'seo_address_region', '');
  final postal = _setting(settings, 'seo_address_postal', '');
  final country = normalizePublicAddressCountry(
    _setting(settings, 'seo_address_country', ''),
  );
  final countryCode = _setting(settings, 'seo_address_country_code', '');
  // Where the store is, from its Google place (`google-public-data-refresh`
  // and the editor's sync): only a pair of real coordinates.
  final latitude = double.tryParse(_setting(settings, 'seo_geo_latitude', ''));
  final longitude = double.tryParse(
    _setting(settings, 'seo_geo_longitude', ''),
  );
  final geo =
      latitude != null &&
      longitude != null &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      !(latitude == 0 && longitude == 0);
  final instagram = _setting(settings, 'instagram', '');
  final url = _setting(settings, 'store_url', '');

  final node = <String, dynamic>{
    '@context': 'https://schema.org',
    '@type': 'BikeStore',
    '@id': '$url/#negocio',
    'name': name,
    'legalName': legalName,
    'taxID': taxId,
    'telephone': phone,
    'email': email,
    'url': url,
    'address': {
      '@type': 'PostalAddress',
      'streetAddress': normalizePublicStreetAddress(streetRaw, city, country),
      'addressLocality': city,
      'addressRegion': region,
      'postalCode': postal,
      // Google asks for the ISO code; the name until the place gives it.
      'addressCountry': RegExp(r'^[A-Z]{2}$').hasMatch(countryCode)
          ? countryCode
          : country,
    },
    if (geo)
      'geo': {
        '@type': 'GeoCoordinates',
        'latitude': latitude,
        'longitude': longitude,
      },
    'areaServed': {'@type': 'Country', 'name': country},
    'contactPoint': {
      '@type': 'ContactPoint',
      'contactType': 'customer support',
      'telephone': phone,
      'email': email,
      'availableLanguage': ['es'],
      if (countryCode.isNotEmpty) 'areaServed': countryCode,
    },
    if (instagram.isNotEmpty) 'sameAs': [instagram],
  };
  return node;
}
