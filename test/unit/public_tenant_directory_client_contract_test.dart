import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public tenant discovery never reads the tenants authority table', () {
    final source = File(
      'lib/shared/services/tenant_detection_service.dart',
    ).readAsStringSync();

    final publicLookupStart =
        source.indexOf('Future<Tenant?> _getTenantBySubdomainOrDomain');
    final authenticatedLookupStart =
        source.indexOf('Future<Tenant?> _getTenantFromAuthenticatedUser');
    expect(publicLookupStart, isNot(-1));
    expect(authenticatedLookupStart, greaterThan(publicLookupStart));

    final publicDetection =
        source.substring(publicLookupStart, authenticatedLookupStart);
    expect(publicDetection, contains(".from('public_tenant_directory')"));
    expect(publicDetection, isNot(contains(".from('tenants')")));

    final availabilityStart =
        source.indexOf('Future<bool> isSubdomainAvailable');
    expect(availabilityStart, greaterThan(authenticatedLookupStart));
    final authenticatedLookup =
        source.substring(authenticatedLookupStart, availabilityStart);
    expect(authenticatedLookup, contains(".from('tenants')"));

    final availability = source.substring(availabilityStart);
    expect(availability, contains(".from('public_tenant_directory')"));
    expect(availability, contains(".from('public_reserved_subdomains')"));
    expect(availability, isNot(contains(".from('tenants')")));
    expect(availability, isNot(contains(".from('reserved_subdomains')")));
  });

  test('remaining tenant-table calls are authenticated own-tenant surfaces',
      () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file.readAsStringSync().contains(".from('tenants')"),
        )
        .map((file) => file.path)
        .toSet();

    expect(
      files,
      {
        'lib/modules/settings/pages/settings_page.dart',
        'lib/modules/settings/services/company_profile_service.dart',
        'lib/public_store/widgets/public_store_layout.dart',
        'lib/shared/services/tenant_detection_service.dart',
        'lib/shared/services/tenant_service.dart',
      },
    );
  });
}
