import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap requests an active CMS page origin revalidation', () {
    final service = File(
      'lib/modules/website/services/website_service.dart',
    ).readAsStringSync();
    final bootstrap = File(
      'lib/public_store/widgets/public_store_bootstrap.dart',
    ).readAsStringSync();

    expect(
        service, contains('ValueListenable<int> get cmsPageFreshnessSignal'));
    expect(
      service,
      contains('void requestActiveCmsPageOriginRevalidation()'),
    );
    expect(service, contains('_cmsPageFreshnessSignal.dispose()'));

    final websitePulse = bootstrap.substring(
      bootstrap.indexOf('if (websiteDue) {'),
      bootstrap.indexOf(
        "} catch (error) {",
        bootstrap.indexOf('if (websiteDue) {'),
      ),
    );
    expect(websitePulse, contains('loadPublicStoreDataUnified('));
    expect(
      websitePulse,
      contains('requestActiveCmsPageOriginRevalidation()'),
    );
  });

  test('CMS page owners refresh only while ticker-enabled', () {
    final pageContracts = <String, String>{
      'dynamic': File(
        'lib/public_store/pages/dynamic_website_page.dart',
      ).readAsStringSync(),
      'policy': File(
        'lib/public_store/pages/static_policy_page.dart',
      ).readAsStringSync(),
    };

    for (final entry in pageContracts.entries) {
      final source = entry.value;
      expect(
        source,
        contains(
          '.cmsPageFreshnessSignal\n'
          '          .addListener(_handleCmsPageFreshnessSignal)',
        ),
        reason: '${entry.key} must observe the explicit CMS signal',
      );
      expect(
        source,
        contains(
          '.cmsPageFreshnessSignal\n'
          '        .removeListener(_handleCmsPageFreshnessSignal)',
        ),
        reason: '${entry.key} must detach its listener',
      );
      expect(
        source,
        contains('if (!TickerMode.of(context)) {'),
        reason: '${entry.key} must defer refresh while offstage',
      );
      expect(
        source,
        contains('_cmsRevalidationPending = true;'),
        reason: '${entry.key} must remember an offstage pulse',
      );
      expect(
        source,
        contains('void _scheduleCmsPageOriginRevalidation()'),
        reason: '${entry.key} must coalesce refresh scheduling',
      );
    }
  });
}
