import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/services/google_business_service.dart';
import 'package:vinabike_public_core/public_store/seo/public_business_identity.dart';

/// The store's place in its business node (2026-10-07): Google recommends
/// `geo` and the country by its ISO code for a local business, and until
/// then no owner had the coordinates. The daily Google refresh and the
/// editor's sync write them from the store's own place.
void main() {
  const base = {
    'store_name': 'Viñabike',
    'store_url': 'https://vinabike.cl',
    'seo_address_street': 'Alvarez 32',
    'seo_address_city': 'Viña del Mar',
    'seo_address_country': 'Chile',
  };

  test('the node carries the place and the country code once known', () {
    final node = buildPublicBusinessIdentity({
      ...base,
      'seo_address_country_code': 'CL',
      'seo_geo_latitude': '-33.024537',
      'seo_geo_longitude': '-71.551899',
    });
    expect((node['address'] as Map)['addressCountry'], 'CL');
    expect(node['geo'], {
      '@type': 'GeoCoordinates',
      'latitude': -33.024537,
      'longitude': -71.551899,
    });
    // The area served still names the country.
    expect((node['areaServed'] as Map)['name'], 'Chile');
  });

  test(
      'without them, the country by name and no coordinates; nonsense is '
      'left out', () {
    final unknown = buildPublicBusinessIdentity(base);
    expect((unknown['address'] as Map)['addressCountry'], 'Chile');
    expect(unknown.containsKey('geo'), isFalse);
    for (final (lat, lng) in [('0', '0'), ('91', '10'), ('x', '-71.5')]) {
      final node = buildPublicBusinessIdentity({
        ...base,
        'seo_address_country_code': 'Chile',
        'seo_geo_latitude': lat,
        'seo_geo_longitude': lng,
      });
      expect(node.containsKey('geo'), isFalse, reason: '$lat,$lng');
      expect((node['address'] as Map)['addressCountry'], 'Chile');
    }
  });

  test('the editor\'s sync takes them from the Business Profile location', () {
    final location = GoogleLocation.fromJson({
      'name': 'locations/1',
      'title': 'Viñabike',
      'latlng': {'latitude': -33.0245371, 'longitude': -71.5518994},
      'storefrontAddress': {
        'regionCode': 'cl',
        'addressLines': ['Alvarez 32'],
      },
    });
    expect(location.placeSettings, {
      'seo_geo_latitude': '-33.024537',
      'seo_geo_longitude': '-71.551899',
      'seo_address_country_code': 'CL',
    });
    expect(
      GoogleLocation.fromJson({'name': 'locations/2', 'title': 'X'})
          .placeSettings,
      isEmpty,
    );
  });
}
