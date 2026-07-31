import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the three ways the stock movements module used to state, with
/// confidence, something it could not know.
///
/// All three were found by a production audit on 2026-07-27. None of them was a
/// consequence of the Zoho migration: they were live code computing a certain
/// answer from an uncertain or incomplete input, which is the failure mode this
/// module exists to prevent.
void main() {
  test('period totals are not computed over a truncated window', () {
    final service = File(
      'lib/modules/inventory/services/stock_movements_service.dart',
    ).readAsStringSync();
    final page = File(
      'lib/modules/inventory/pages/stock_movements_page.dart',
    ).readAsStringSync();

    // The date range must reach the query. Filtering the newest rows in memory
    // answers a different question: picking a past month returned only the rows
    // of that month that survived inside the global tail, and the summary
    // presented those as the period's totals.
    // The range must bound the same instant the ledger is ordered by. Bounding
    // a different column can admit a row whose neighbours were excluded, and
    // the reconstructed balance chain then breaks at the edges of the range.
    expect(
      service,
      matches(RegExp(r"query\.gte\(\s*'created_at'")),
    );
    expect(
      service,
      matches(RegExp(r"query\.lt\(\s*'created_at'")),
      reason: 'The upper bound must be exclusive on the following day; '
          'comparing against the end date at 00:00 drops that whole day.',
    );

    // Filters must compose. Two independent projections of the full list meant
    // the second silently discarded the first, so the type filter never applied.
    expect(service, isNot(contains('List<StockMovement> filterByType(')));
    expect(service, isNot(contains('List<StockMovement> filterByDateRange(')));
    expect(service, contains('get visibleMovements'));
    expect(page, contains('movementsService.visibleMovements'));
    expect(page, contains('storeTimezone: service.storeTimezone'));
    expect(page, contains('final lastDate = DateTime(storeNow.year'));
    expect(page, isNot(contains('lastDate: DateTime.now()')));
    expect(service, contains('_StockMovementQueryScope? _loadedScope'));
    expect(service, contains('requestedScope != _loadedScope'));
    expect(service, isNot(contains('return [];')));

    // When the window really is capped, the UI has to say so.
    expect(service, contains('get isWindowTruncated'));
    expect(page, contains('isWindowTruncated'));

    // Changing a filter must reach the service rather than only setState.
    expect(page, contains('_pushFilters()'));
  });

  test('a reconstructed balance is never presented as source evidence', () {
    final model = File(
      'lib/modules/inventory/models/stock_movement.dart',
    ).readAsStringSync();
    final inspector = File(
      'lib/modules/inventory/widgets/movement_inspector.dart',
    ).readAsStringSync();

    // The database already reports whether a source document recorded the
    // balance. Only those two provenances are real evidence; everything else is
    // a backward reconstruction and must not be labelled "Evidencia fuente".
    expect(model, contains('hasRecordedSourceBalance'));
    expect(model, contains("evidenceBalanceProvenance == 'stock_adjustment'"));
    expect(
      model,
      contains("evidenceBalanceProvenance == 'legacy_collision_adjustment'"),
    );
    expect(inspector, contains('movement.hasRecordedSourceBalance'));
    expect(inspector, contains('Saldo de origen no registrado'));
  });

  test('the product movements tab keeps INICIAL + CAMBIO == FINAL', () {
    final tab = File(
      'lib/modules/inventory/widgets/product_movements_tab.dart',
    ).readAsStringSync();

    // stockBefore and stockAfter come from the reconciled chain, so the change
    // column must use reconciledQuantity. Printing the raw quantity beside them
    // made the three columns disagree on rows the ledger had already corrected.
    expect(tab, contains('move.reconciledQuantity'));
    expect(
      tab.contains('move.stockBefore') && tab.contains('move.stockAfter'),
      isTrue,
      reason: 'The balances themselves must still come from the chain.',
    );
    expect(
      RegExp(r'\$\{move\.quantity\}').hasMatch(tab),
      isFalse,
      reason: 'The raw quantity must not be rendered next to chain balances.',
    );
  });

  test('ordering and period scope are decided by the query', () {
    final service = File(
      'lib/modules/inventory/services/stock_movements_service.dart',
    ).readAsStringSync();

    // The ledger is ordered by the instant it was written, because almost
    // every legacy row's balance is reconstructed by walking backwards in that
    // same order. Ordering by the document's business date — which can differ
    // by days — presents the rows in a sequence the reconstruction never used,
    // and each row's closing balance stops matching the next row's opening one.
    expect(service, contains("order('created_at'"));
    expect(
      service,
      isNot(contains("order('transaction_date'")),
      reason: 'The business date is a fact about the document, not the '
          "ledger's sequence.",
    );

    // Sorting must reach the query. Ordering the loaded page would sort the
    // window instead of the ledger — the same defect the date filter had.
    expect(service, contains('enum MovementSortKey'));
    expect(service, contains('Future<void> applySort('));
    expect(service, contains('order('));
    expect(
      service.indexOf('MovementSortKey sortKey = MovementSortKey.date'),
      greaterThan(-1),
      reason: '_fetchMovements must take the sort key.',
    );

    // A period is a scope an operator can reason about; a row count is not.
    expect(service, contains('defaultPeriod = Duration(days: 30)'));
    expect(service, contains('static DateTimeRange defaultRange()'));

    // A failed refresh must never present itself as an empty ledger.
    expect(
      RegExp(r'catch[\s\S]{0,200}_movements = \[\]').hasMatch(service),
      isFalse,
      reason: 'The error path must keep the rows already on screen.',
    );
  });

  test('inspection responses cannot cross the current movement selection', () {
    final page = File(
      'lib/modules/inventory/pages/stock_movements_page.dart',
    ).readAsStringSync();

    expect(page, contains('_linkedDocumentRequestGeneration'));
    expect(page, contains('_isCurrentDocumentRequest('));
    expect(page, contains('_operationTraceRequestGeneration'));
    expect(page, contains('_isCurrentTraceRequest('));
    expect(page, contains('operationTrace: _selectedOperationTrace'));
    expect(page, contains('operationTraceError: _operationTraceError'));
  });

  test('an explicit all-period scope survives later realtime reloads', () {
    final page = File(
      'lib/modules/inventory/pages/stock_movements_page.dart',
    ).readAsStringSync();

    expect(page, contains('_pushFilters(explicitAllPeriod: true)'));
    expect(page, contains('await service.clearPeriod()'));
    expect(
      page,
      contains('await service.applyFilters(\n'
          '        type: _movementTypeFilter,\n'
          '        refetch: false,'),
    );
  });
}
