import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/stock_movement.dart';
import 'package:vinabike_erp/modules/inventory/services/stock_movements_service.dart';
import 'package:vinabike_erp/modules/inventory/widgets/stock_ledger.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';

/// Renders the ledger for real at every width it supports.
///
/// The analyzer cannot see a `Container` given both `color` and `decoration`,
/// a missing locale, or an unbounded constraint: they are runtime assertions
/// that only fire when a frame is actually painted. A ledger that compiles
/// cleanly and then renders an empty pane is exactly the failure this file
/// exists to stop, so every test here paints and then asserts on pixels or
/// text — never on source.
void main() {
  final movements = <StockMovement>[
    _movement(
      id: 'a',
      date: DateTime(2026, 7, 27, 14, 32),
      quantity: -2,
      before: 11,
      after: 9,
      reference: 'FV-00906',
    ),
    _movement(
      id: 'b',
      date: DateTime(2026, 7, 27, 9, 5),
      quantity: 10,
      before: 1,
      after: 11,
      reference: 'REC-0003',
    ),
    // A second day, so the day-grouping path is exercised.
    _movement(
      id: 'c',
      date: DateTime(2026, 7, 24, 22, 12),
      quantity: -1,
      before: 2,
      after: 1,
      reference: 'FV-00902',
      warning: true,
    ),
  ];

  Widget host(
    List<StockMovement> rows, {
    required Size size,
    bool chronological = true,
    MovementSortKey sortKey = MovementSortKey.date,
    bool ascending = false,
    void Function(MovementSortKey)? onSort,
    String storeTimezone = stockMovementsDefaultStoreTimezone,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SizedBox(
          width: size.width,
          height: size.height,
          child: StockLedger(
            movements: rows,
            chronological: chronological,
            sortKey: sortKey,
            ascending: ascending,
            storeTimezone: storeTimezone,
            onSort: onSort ?? (_) {},
            onOpen: (_) {},
          ),
        ),
      ),
    );
  }

  for (final size in const [
    Size(1440, 800), // desktop, every column
    Size(980, 800), // reference column dropped
    Size(600, 800), // stacked rows
  ]) {
    testWidgets(
      'ledger paints at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(host(movements, size: size));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'A ledger that throws while painting renders as a blank pane, '
              'which looks identical to "you have no movements".',
        );
        expect(find.byType(StockLedger), findsOneWidget);
        // Something real must be on screen, not just an empty viewport.
        expect(find.textContaining('Cadena KMC'), findsWidgets);

        // The reference is the document that justifies the line, so it
        // survives at every width — a row that asserts a stock change with no
        // evidence beside it is not a ledger entry.
        expect(find.textContaining('FV-00906'), findsWidgets);

        // The SKU yields instead: the product name already identifies the row
        // and the SKU is a lookup key, not evidence.
        expect(
          find.textContaining('4715575883212'),
          size.width >= 1120 ? findsWidgets : findsNothing,
        );
      },
    );
  }

  testWidgets('chronological order groups rows under day headers',
      (tester) async {
    await tester.pumpWidget(host(movements, size: const Size(1440, 800)));
    await tester.pumpAndSettle();

    // 2026-07-27 and 2026-07-24 are different days, so both headers exist.
    // The labels are built without a locale on purpose: asking intl for 'es'
    // throws in this app and took the whole ledger down with it.
    expect(find.textContaining('de julio'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ledger groups and formats instants on the store calendar',
      (tester) async {
    final crossMidnight = [
      _movement(
        id: 'timezone-before',
        date: DateTime.utc(2025, 7, 28, 2, 30),
        quantity: 1,
        before: 0,
        after: 1,
        reference: 'AJ-0100',
      ),
      _movement(
        id: 'timezone-after',
        date: DateTime.utc(2025, 7, 28, 4, 30),
        quantity: 1,
        before: 1,
        after: 2,
        reference: 'AJ-0101',
      ),
    ];

    await tester.pumpWidget(
      host(
        crossMidnight,
        size: const Size(1440, 800),
        storeTimezone: 'America/Santiago',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('22:30'), findsOneWidget);
    expect(find.text('00:30'), findsOneWidget);
    expect(find.textContaining('de julio'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ranked order drops day headers', (tester) async {
    await tester.pumpWidget(
      host(
        movements,
        size: const Size(1440, 800),
        chronological: false,
        sortKey: MovementSortKey.change,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('de julio'),
      findsNothing,
      reason: 'Under a ranked order consecutive rows are unrelated in time, so '
          'a day header would group rows that have nothing in common.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact ledger exposes a touch-safe ordering alternative',
      (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MovementSortKey? selectedSort;

    await tester.pumpWidget(
      host(
        movements,
        size: const Size(600, 800),
        onSort: (key) => selectedSort = key,
      ),
    );
    await tester.pumpAndSettle();

    final sortControl = find.text('Orden: Fecha');
    expect(sortControl, findsOneWidget);
    expect(
      tester
          .getSize(find
              .ancestor(
                of: sortControl,
                matching: find.byType(ConstrainedBox),
              )
              .first)
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(sortControl);
    await tester.pumpAndSettle();
    expect(find.text('Ordenar por cambio'), findsOneWidget);

    await tester.tap(find.text('Ordenar por cambio'));
    await tester.pumpAndSettle();
    expect(selectedSort, MovementSortKey.change);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty ledger still paints its frame', (tester) async {
    await tester.pumpWidget(host(const [], size: const Size(1440, 800)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a row carries its transition, its origin and its caveat',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(movements, size: const Size(1440, 800)));
    await tester.pumpAndSettle();

    // The transition, not just the closing balance: reconstructing the opening
    // one from the row above stops working the moment the list is filtered.
    expect(find.textContaining('11 → 9'), findsWidgets);

    // Type and origin together. "Venta" alone loses where it happened,
    // "Taller" alone loses that it was a sale.
    expect(find.textContaining('·'), findsWidgets);

    // A gutter mark says something is worth checking; it never says what.
    expect(find.textContaining('Huella duplicada'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('type and origin never print the same word twice',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      host(
        [
          _movement(
            id: 'dup',
            date: DateTime(2026, 7, 27, 10),
            quantity: -1,
            before: 3,
            after: 2,
            reference: 'FV-1',
            sameTypeAndOrigin: true,
          )
        ],
        size: const Size(1440, 800),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Venta · Venta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the running balance chains down the ledger', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Newest first, so reading downwards walks backwards in time: every row's
    // opening balance must be the closing balance of the row below it. This is
    // the one invariant a ledger has, and it only holds while the rows are
    // shown in the order their balances were computed in.
    final chained = <StockMovement>[
      _movement(
        id: '1',
        date: DateTime(2026, 7, 15, 18, 51),
        quantity: -1,
        before: 6,
        after: 5,
        reference: 'FV-00881',
      ),
      _movement(
        id: '2',
        date: DateTime(2026, 7, 9, 22, 37),
        quantity: -1,
        before: 7,
        after: 6,
        reference: 'FV-00843',
      ),
      _movement(
        id: '3',
        date: DateTime(2026, 7, 7, 21, 48),
        quantity: -1,
        before: 8,
        after: 7,
        reference: 'FV-00827',
      ),
      _movement(
        id: '4',
        date: DateTime(2026, 7, 6, 17, 47),
        quantity: -1,
        before: 9,
        after: 8,
        reference: 'FV-00831',
      ),
    ];

    await tester.pumpWidget(host(chained, size: const Size(1440, 900)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Each transition is rendered as one string, so the chain is verifiable
    // from what the operator actually sees.
    for (final pair in const ['6 → 5', '7 → 6', '8 → 7', '9 → 8']) {
      expect(find.textContaining(pair), findsOneWidget,
          reason: 'missing $pair');
    }

    // And the fixture itself must chain, or the assertion above proves nothing.
    for (var i = 0; i < chained.length - 1; i++) {
      expect(
        chained[i].stockBefore,
        chained[i + 1].stockAfter,
        reason: 'row $i opens where row ${i + 1} closed',
      );
    }
  });
}

StockMovement _movement({
  required String id,
  required DateTime date,
  required int quantity,
  required int before,
  required int after,
  required String reference,
  bool warning = false,
  bool sameTypeAndOrigin = false,
}) {
  return StockMovement(
    id: id,
    productId: 'p-$id',
    productName: 'Cadena KMC Hv408',
    productSku: '4715575883212',
    transactionDate: date,
    movementType: quantity >= 0 ? 'purchase' : 'sale',
    source: sameTypeAndOrigin
        ? 'Venta'
        : (quantity >= 0 ? 'Recepción de compra' : 'Taller'),
    referenceId: reference,
    referenceNumber: reference,
    stockBefore: before,
    quantity: quantity,
    stockAfter: after,
    rawQuantity: quantity,
    actualStockDelta: quantity,
    reconciledQuantity: quantity,
    balanceProvenance: 'persisted_movement',
    integrityStatus: warning ? 'legacy_duplicate_footprint' : 'verified',
    isSummaryExcluded: false,
    evidenceStockBefore: before,
    evidenceStockAfter: after,
    evidenceBalanceProvenance: 'persisted_movement',
    evidenceIntegrityStatus:
        warning ? 'legacy_duplicate_footprint' : 'verified',
    createdAt: date,
  );
}
