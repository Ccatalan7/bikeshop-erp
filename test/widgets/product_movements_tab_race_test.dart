import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/inventory/models/stock_movement.dart';
import 'package:vinabike_erp/modules/inventory/services/stock_movements_service.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_movements_tab.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';

void main() {
  testWidgets('a failed load offers retry and a successful retry paints rows',
      (tester) async {
    var calls = 0;
    final service = _TestStockMovementsService(
      load: (productId) async {
        calls++;
        if (calls == 1) {
          throw StateError('temporary transport failure');
        }
        return [
          _movement(
            id: 'retry-success',
            productId: productId,
            reference: 'AJ-RETRY',
          ),
        ];
      },
    );
    addTearDown(service.close);

    await tester.pumpWidget(_host(productId: 'product-a', service: service));
    await _pumpUntilFound(tester, find.text('Reintentar'));

    expect(find.text('Error cargando movimientos'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('AJ-RETRY'), findsNothing);

    await tester.tap(find.text('Reintentar'));
    await _pumpUntilFound(tester, find.text('AJ-RETRY'));

    expect(calls, 2);
    expect(find.text('Reintentar'), findsNothing);
    expect(find.text('AJ-RETRY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late response for the previous product cannot replace rows',
      (tester) async {
    final productA = Completer<List<StockMovement>>();
    final productB = Completer<List<StockMovement>>();
    final requested = <String>[];
    final service = _TestStockMovementsService(
      load: (productId) {
        requested.add(productId);
        return productId == 'product-a' ? productA.future : productB.future;
      },
    );
    addTearDown(service.close);

    await tester.pumpWidget(_host(productId: 'product-a', service: service));
    await tester.pump();
    expect(requested, ['product-a']);

    await tester.pumpWidget(_host(productId: 'product-b', service: service));
    await tester.pump();
    expect(requested, ['product-a', 'product-b']);

    productB.complete([
      _movement(
        id: 'current-b',
        productId: 'product-b',
        reference: 'ROW-B',
      ),
    ]);
    await _pumpUntilFound(tester, find.text('ROW-B'));
    expect(find.text('ROW-B'), findsOneWidget);
    expect(find.text('ROW-A'), findsNothing);

    productA.complete([
      _movement(
        id: 'stale-a',
        productId: 'product-a',
        reference: 'ROW-A',
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ROW-B'), findsOneWidget);
    expect(find.text('ROW-A'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('movement instants are formatted in the store timezone',
      (tester) async {
    final service = _TestStockMovementsService(
      storeTimezone: 'America/Santiago',
      load: (productId) async => [
        _movement(
          id: 'timezone-row',
          productId: productId,
          reference: 'TZ-ROW',
          transactionDate: DateTime.utc(2026, 7, 28, 2, 30),
        ),
      ],
    );
    addTearDown(service.close);

    await tester.pumpWidget(_host(productId: 'product-a', service: service));
    await _pumpUntilFound(tester, find.text('TZ-ROW'));

    expect(find.text('27 Jul 2026, 22:30'), findsOneWidget);
    expect(find.textContaining('28 Jul 2026, 02:30'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _host({
  required String productId,
  required StockMovementsService service,
}) {
  return ChangeNotifierProvider<StockMovementsService>.value(
    value: service,
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 600,
          child: ProductMovementsTab(productId: productId),
        ),
      ),
    ),
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the expected widget.');
}

class _TestStockMovementsService extends StockMovementsService {
  factory _TestStockMovementsService({
    required Future<List<StockMovement>> Function(String productId) load,
    String storeTimezone = stockMovementsDefaultStoreTimezone,
  }) {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(
          'Test service must not make network requests.',
          500,
          request: request,
        ),
      ),
    );
    return _TestStockMovementsService._(
      client: client,
      load: load,
      testStoreTimezone: storeTimezone,
    );
  }

  _TestStockMovementsService._({
    required SupabaseClient client,
    required this.load,
    required this.testStoreTimezone,
  }) : super(
          supabase: client,
          tenantService: TenantService.testing(
            currentUserId: () => null,
            profileLookup: (_) async => const [],
          ),
          enableRealtime: false,
        );

  final Future<List<StockMovement>> Function(String productId) load;
  final String testStoreTimezone;

  @override
  String get storeTimezone => testStoreTimezone;

  @override
  Future<List<StockMovement>> getMovementsList(String productId) {
    return load(productId);
  }

  void close() {
    dispose();
  }
}

StockMovement _movement({
  required String id,
  required String productId,
  required String reference,
  DateTime? transactionDate,
}) {
  final date = transactionDate ?? DateTime.utc(2026, 7, 28, 12);
  return StockMovement(
    id: id,
    productId: productId,
    productName: 'Cadena de prueba',
    productSku: 'TEST-SKU',
    transactionDate: date,
    movementType: 'adjustment',
    source: 'Ajuste de stock',
    referenceId: reference,
    referenceNumber: reference,
    stockBefore: 2,
    quantity: 1,
    stockAfter: 3,
    rawQuantity: 1,
    actualStockDelta: 1,
    reconciledQuantity: 1,
    balanceProvenance: 'persisted_movement',
    integrityStatus: 'verified',
    isSummaryExcluded: false,
    evidenceStockBefore: 2,
    evidenceStockAfter: 3,
    evidenceBalanceProvenance: 'persisted_movement',
    evidenceIntegrityStatus: 'verified',
    createdAt: date,
  );
}
