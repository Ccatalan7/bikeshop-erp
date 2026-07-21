import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String finder;
  late String router;
  late String jobForm;
  late String jobsTable;
  late String visibilityPolicy;
  late String registry;

  setUpAll(() {
    finder = File(
      'lib/shared/widgets/quick_bike_finder_panel.dart',
    ).readAsStringSync();
    router = File('lib/shared/routes/app_router.dart').readAsStringSync();
    jobForm = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    jobsTable = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();
    visibilityPolicy = File(
      'lib/modules/bikeshop/services/mechanic_job_visibility_policy.dart',
    ).readAsStringSync();
    registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();
  });

  test('finder stays bounded and uses one contextual scope menu', () {
    expect(finder, contains('PopupMenuButton<_BikeFinderScope>'));
    expect(finder, contains('_BikeFinderScope.activeJobs'));
    expect(finder, contains('_BikeFinderScope.warranty'));
    expect(finder, contains('_BikeFinderScope.archived'));
    expect(finder, contains('final limit = isRecentOverview ? 18 : 60'));
    expect(finder, contains('results.take(limit)'));

    expect(finder, isNot(contains('ChoiceChip')));
    expect(finder, isNot(contains('FilterChip')));
    expect(finder, isNot(contains('DropdownButtonFormField')));
    expect(finder, isNot(contains('_expandedCustomerIds')));
    expect(finder, isNot(contains('_buildFinderActionButton')));
  });

  test('finder searches operational identity and routes to canonical hosts',
      () {
    expect(finder, contains('bikeFinderRelationalSearchScore('));
    expect(finder, contains('BikeFinderSearchField(bike.serialNumber'));
    expect(finder, contains('BikeFinderSearchField(bike.qrCode'));
    expect(finder, contains('BikeFinderSearchField(owner?.phone'));
    expect(finder, contains('BikeFinderSearchField(owner?.name'));

    expect(finder, contains("path: '/clientes/\$customerId'"));
    expect(finder, contains("'bike_id': bikeId"));
    expect(finder, contains("path: '/taller/pegas/nueva'"));
    expect(finder, contains("'/taller/pegas/\$jobId'"));
    expect(finder, contains("'/taller/bicicletas'"));
    expect(finder, contains("path: '/sales/invoices'"));
    expect(finder, contains("'selectedInvoiceId': invoiceId"));
    expect(finder, contains("'view': 'split'"));
    expect(finder, contains('if (!bike.isActive ||'));
  });

  test('new-job route preserves and validates the selected bicycle', () {
    expect(
      router,
      contains("initialBikeId: state.uri.queryParameters['bike_id']"),
    );
    expect(jobForm, contains('final String? initialBikeId'));
    expect(jobForm, contains('_findBikeById(widget.initialBikeId)'));
    expect(jobForm, contains('initialBike.isActive'));
    expect(jobForm, contains('initialBike.customerId == customer.id'));
    expect(jobForm, contains('_addBikeTab(initialBike)'));
  });

  test('finder and Jobs table share workshop visibility classification', () {
    expect(finder, contains('isMechanicJobBikeInWorkshop('));
    expect(finder, contains('mechanicJobMatchesTestFixture('));
    expect(finder, contains('right.metrics.lastActivityAt'));
    expect(finder, contains('final lastActivity = metrics.lastActivityAt'));
    expect(finder, contains("title: Text('Abrir último trabajo')"));
    expect(finder, contains("? 'Factura' : 'Último trabajo'"));
    expect(finder, contains("label: canOpenLatestJob ? 'Nuevo'"));
    expect(jobsTable, contains('isMechanicJobCurrentlyDelivered(job)'));
    expect(jobsTable, contains('mechanicJobMatchesTestFixture('));
    expect(visibilityPolicy, contains('JobStatus.cancelado'));
    expect(visibilityPolicy, contains('triggersDelivery'));
  });

  test('canonical surface registry keeps the finder read-only', () {
    expect(registry, contains('| Quick bicycle finder |'));
    expect(registry, contains('bounded search/navigation read surface'));
    expect(registry, contains('not another editor'));
    expect(registry, contains('customer_id` plus `bike_id'));
  });
}
