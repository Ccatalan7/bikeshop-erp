import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('existing job editor blocks only on exact aggregate data', () {
    final source = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    final loadStart = source.indexOf('Future<void> _loadInitialData() async');
    final loadEnd = source.indexOf(
      'Future<\n      ({\n        String? invoiceNumber,',
      loadStart,
    );

    expect(loadStart, greaterThanOrEqualTo(0));
    expect(loadEnd, greaterThan(loadStart));
    final initialLoad = source.substring(loadStart, loadEnd);
    final existingEditorBranch = initialLoad.indexOf(
      'if (widget.jobId != null) {',
    );
    final broadCustomerCatalog = initialLoad.indexOf(
      'customerService.getCustomersForList()',
    );

    expect(existingEditorBranch, greaterThanOrEqualTo(0));
    expect(broadCustomerCatalog, greaterThan(existingEditorBranch));
    expect(
      initialLoad.substring(existingEditorBranch, broadCustomerCatalog),
      allOf(contains('await _loadExistingJob();'), contains('return;')),
      reason:
          'Existing jobs must render from exact job/customer/bike/line reads before any broad selector catalog.',
    );
  });

  test('existing editor batches line profiles and defers dormant consumers',
      () {
    final form = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    final existingLoadStart = form.indexOf(
      'Future<void> _loadExistingJob() async',
    );
    final existingLoadEnd = form.indexOf(
      'Future<void> _selectCustomer(',
      existingLoadStart,
    );
    final existingLoad = form.substring(existingLoadStart, existingLoadEnd);

    expect(
      existingLoad,
      contains('getProfilesForProducts(directCatalogProductIds)'),
    );
    expect(existingLoad, contains('includeOperationalProjections: false'));
    expect(
      existingLoad,
      isNot(contains('getProfileForProduct(')),
      reason:
          'A loaded service line must not issue its own three-read profile waterfall.',
    );
    expect(form, contains('preloadCatalog: false'));
    expect(form, contains('deferLoadingUntilExpanded: true'));
  });
}
