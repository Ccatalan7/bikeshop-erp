import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/services/google_business_service.dart';
import 'package:vinabike_public_core/public_store/seo/public_business_identity.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

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

  test('the build checks the Flutter store\'s node with the same country', () {
    // The store publication of 2026-10-07 failed: the shell said `CL` once
    // the place gave the code, and the check still expected `Chile`.
    expect(
      snapshots.buildExpectedLocalBusinessIdentity({
        ...base,
        'seo_address_country_code': 'CL',
      }, storeUrl: 'https://vinabike.cl')['address.addressCountry'],
      'CL',
    );
    expect(
      snapshots.buildExpectedLocalBusinessIdentity(
        base,
        storeUrl: 'https://vinabike.cl',
      )['address.addressCountry'],
      'Chile',
    );
  });

  test('the index generator reads the settings trimmed, as the server does',
      () async {
    // `sync_seo_index.sh` builds the same node for the Flutter store's
    // index.html; until 2026-10-08 it read `"CL "` as no code and a padded
    // latitude as no `geo` while the HTML server trimmed them.
    final script = File('scripts/sync_seo_index.sh').readAsStringSync();
    final reader =
        RegExp(r'^get_setting\(\) \{\n.*?^\}', multiLine: true, dotAll: true)
            .firstMatch(script)!
            .group(0)!;
    final settings = jsonEncode([
      {'key': 'seo_address_country_code', 'value': 'CL '},
      {'key': 'seo_geo_latitude', 'value': ' -33.025195\n'},
      {'key': 'seo_phone', 'value': '   '},
    ]);
    final result = await Process.run('bash', [
      '-c',
      '$reader\n'
          'get_setting seo_address_country_code x\n'
          'get_setting seo_geo_latitude x\n'
          'get_setting seo_phone fallback\n',
    ], environment: {
      ...Platform.environment,
      'SETTINGS': settings
    });
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      const LineSplitter().convert(result.stdout as String),
      ['CL', '-33.025195', 'fallback'],
    );
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
