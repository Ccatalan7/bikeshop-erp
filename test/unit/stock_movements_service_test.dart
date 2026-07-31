import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/inventory/services/stock_movements_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantId = '91000000-0000-4000-8000-000000000001';
const _productId = '91000000-0000-4000-8000-000000000002';

void main() {
  test('a fresh recent ledger is loading before its first scheduled request',
      () {
    final service = _serviceWithRows(totalRows: 0, requests: <Uri>[]);

    expect(service.isRecentMode, isTrue);
    expect(service.isLoading, isTrue);
    expect(service.movements, isEmpty);
  });

  group('stock movement pagination', () {
    test('a stale request cannot overwrite a newer product scope', () async {
      const firstProduct = '91000000-0000-4000-8000-000000000010';
      const secondProduct = '91000000-0000-4000-8000-000000000011';
      final firstResponse = Completer<http.Response>();
      final secondResponse = Completer<http.Response>();
      final firstRequested = Completer<void>();
      final secondRequested = Completer<void>();
      late http.BaseRequest firstRequest;
      late http.BaseRequest secondRequest;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) {
          final productFilter = request.url.queryParameters['product_id'];
          if (productFilter == 'eq.$firstProduct') {
            firstRequest = request;
            if (!firstRequested.isCompleted) firstRequested.complete();
            return firstResponse.future;
          }
          if (productFilter == 'eq.$secondProduct') {
            secondRequest = request;
            if (!secondRequested.isCompleted) secondRequested.complete();
            return secondResponse.future;
          }
          throw StateError('Unexpected product filter: $productFilter');
        }),
      );
      addTearDown(client.dispose);
      final service = StockMovementsService(
        supabase: client,
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        tenantIdLoader: () async => _tenantId,
        storeTimezoneLoader: (_) async => 'America/Santiago',
        enableRealtime: false,
      );
      addTearDown(service.dispose);

      final staleLoad = service.loadMovementsForProduct(firstProduct);
      await firstRequested.future;
      final currentLoad = service.loadMovementsForProduct(secondProduct);
      await secondRequested.future;
      secondResponse.complete(_rowsResponse([
        _movementRow(2, productId: secondProduct),
      ], request: secondRequest));
      await currentLoad;
      firstResponse.complete(_rowsResponse([
        _movementRow(1, productId: firstProduct),
      ], request: firstRequest));
      await staleLoad;

      expect(service.selectedProductId, secondProduct);
      expect(service.movements.single.productId, secondProduct);
      expect(service.movements.single.id, 'movement-2');
      expect(service.isLoading, isFalse);
      expect(service.error, isNull);
    });

    test('loads every row when a result contains more than 1000 movements',
        () async {
      final requests = <Uri>[];
      final service = _serviceWithRows(
        totalRows: 1205,
        requests: requests,
      );

      await service.loadMovementsForProduct(_productId);

      expect(service.error, isNull);
      expect(service.movements, hasLength(1205));
      expect(
        service.movements.map((movement) => movement.id).toSet(),
        hasLength(1205),
      );
      expect(
        requests.map((uri) => uri.queryParameters['offset']),
        ['0', '1000'],
      );
      expect(
        requests.map((uri) => uri.queryParameters['limit']),
        ['1000', '1000'],
      );
      for (final uri in requests) {
        expect(uri.queryParameters['tenant_id'], 'eq.$_tenantId');
        expect(uri.queryParameters['product_id'], 'eq.$_productId');
      }
    });

    test('an exact recent-window row count is not reported as truncated',
        () async {
      final requests = <Uri>[];
      final service = _serviceWithRows(
        totalRows: StockMovementsService.recentWindow,
        requests: requests,
      );

      await service.clearPeriod();

      expect(service.movements, hasLength(StockMovementsService.recentWindow));
      expect(service.isWindowTruncated, isFalse);
      expect(requests, hasLength(1));
      expect(
        requests.single.queryParameters['limit'],
        '${StockMovementsService.recentWindow + 1}',
      );
    });

    test('a recent window fetches one extra row and exposes only its limit',
        () async {
      final requests = <Uri>[];
      final service = _serviceWithRows(
        totalRows: StockMovementsService.recentWindow + 1,
        requests: requests,
      );

      await service.clearPeriod();

      expect(service.movements, hasLength(StockMovementsService.recentWindow));
      expect(service.isWindowTruncated, isTrue);
      expect(requests, hasLength(1));
      expect(
        requests.single.queryParameters['limit'],
        '${StockMovementsService.recentWindow + 1}',
      );
    });

    test('a failed refresh retains rows only for the exact loaded scope',
        () async {
      const firstProduct = '91000000-0000-4000-8000-000000000020';
      const secondProduct = '91000000-0000-4000-8000-000000000021';
      var requestCount = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requestCount++;
          final productFilter = request.url.queryParameters['product_id'];
          if (requestCount == 1 && productFilter == 'eq.$firstProduct') {
            return _rowsResponse([
              _movementRow(1, productId: firstProduct),
            ], request: request);
          }
          return http.Response(
            jsonEncode({'message': 'transport unavailable'}),
            503,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final service = StockMovementsService(
        supabase: client,
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        tenantIdLoader: () async => _tenantId,
        storeTimezoneLoader: (_) async => 'America/Santiago',
        enableRealtime: false,
      );
      addTearDown(service.dispose);

      await service.loadMovementsForProduct(firstProduct);
      expect(service.movements.single.productId, firstProduct);

      await service.loadMovementsForProduct(firstProduct);
      expect(service.error, isNotNull);
      expect(
        service.movements.single.productId,
        firstProduct,
        reason: 'A same-scope refresh may retain its last known book.',
      );

      await service.loadMovementsForProduct(secondProduct);
      expect(service.error, isNotNull);
      expect(
        service.movements,
        isEmpty,
        reason: 'Rows from product A must never paint under product B.',
      );
    });
  });

  test('disposing during tenant resolution never creates realtime channels',
      () async {
    final tenantResolution = Completer<String?>();
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final service = StockMovementsService(
      supabase: client,
      tenantService: TenantService.testing(
        currentUserId: () => null,
        profileLookup: (_) async => const [],
      ),
      tenantIdLoader: () => tenantResolution.future,
    );

    service.dispose();
    tenantResolution.complete(_tenantId);
    await Future<void>.delayed(Duration.zero);

    expect(client.getChannels(), isEmpty);
  });

  group('stock calendar UTC bounds', () {
    test('uses half-open Santiago bounds across a 25-hour DST day', () {
      final bounds = stockMovementUtcDateBounds(
        startDate: DateTime(2026, 4, 4),
        endDate: DateTime(2026, 4, 4),
        storeTimezone: 'America/Santiago',
      );

      expect(bounds.timezone, 'America/Santiago');
      expect(bounds.startInclusive, DateTime.utc(2026, 4, 4, 3));
      expect(bounds.endExclusive, DateTime.utc(2026, 4, 5, 4));
      expect(
        bounds.endExclusive!.difference(bounds.startInclusive!),
        const Duration(hours: 25),
      );
    });

    test('uses half-open Santiago bounds across a 23-hour DST day', () {
      final bounds = stockMovementUtcDateBounds(
        startDate: DateTime(2026, 9, 6),
        endDate: DateTime(2026, 9, 6),
        storeTimezone: 'America/Santiago',
      );

      expect(bounds.timezone, 'America/Santiago');
      expect(bounds.startInclusive, DateTime.utc(2026, 9, 6, 4));
      expect(bounds.endExclusive, DateTime.utc(2026, 9, 7, 3));
      expect(
        bounds.endExclusive!.difference(bounds.startInclusive!),
        const Duration(hours: 23),
      );
    });

    test('sends UTC timestamptz filters and caches the tenant timezone',
        () async {
      final requests = <Uri>[];
      var timezoneLoads = 0;
      final service = _serviceWithRows(
        totalRows: 0,
        requests: requests,
        timezoneLoader: (_) async {
          timezoneLoads++;
          return 'America/Santiago';
        },
      );

      await service.applyFilters(
        startDate: DateTime(2026, 4, 4),
        endDate: DateTime(2026, 4, 4),
      );
      await service.applyFilters(
        startDate: DateTime(2026, 7, 15),
        endDate: DateTime(2026, 7, 15),
      );

      expect(service.error, isNull);
      expect(service.storeTimezone, 'America/Santiago');
      expect(timezoneLoads, 1);
      expect(requests, hasLength(2));
      expect(
        requests.first.queryParametersAll['created_at'],
        containsAll([
          'gte.${DateTime.utc(2026, 4, 4, 3).toIso8601String()}',
          'lt.${DateTime.utc(2026, 4, 5, 4).toIso8601String()}',
        ]),
      );
      expect(
        requests.last.queryParametersAll['created_at'],
        containsAll([
          'gte.${DateTime.utc(2026, 7, 15, 4).toIso8601String()}',
          'lt.${DateTime.utc(2026, 7, 16, 4).toIso8601String()}',
        ]),
      );
    });

    test('exposes a resolved non-default tenant timezone to consumers',
        () async {
      var timezoneLoads = 0;
      final service = _serviceWithRows(
        totalRows: 0,
        requests: <Uri>[],
        timezoneLoader: (_) async {
          timezoneLoads++;
          return 'America/New_York';
        },
      );

      await service.loadMovementsForProduct(_productId);
      await service.loadMovementsForProduct(_productId);

      expect(service.storeTimezone, 'America/New_York');
      expect(timezoneLoads, 1);
      final local = stockMovementStoreTime(
        DateTime.utc(2026, 7, 15, 3, 30),
        storeTimezone: service.storeTimezone,
      );
      expect((local.year, local.month, local.day, local.hour, local.minute),
          (2026, 7, 14, 23, 30));
    });

    test('invalid or absent tenant zones use the controlled Chile fallback',
        () {
      final bounds = stockMovementUtcDateBounds(
        startDate: DateTime(2026, 1, 15),
        endDate: DateTime(2026, 1, 15),
        storeTimezone: 'Invalid/Store_Zone',
      );
      final local = stockMovementStoreTime(
        DateTime.utc(2026, 1, 15, 2, 30),
        storeTimezone: 'Invalid/Store_Zone',
      );

      expect(bounds.timezone, stockMovementsDefaultStoreTimezone);
      expect(bounds.startInclusive, DateTime.utc(2026, 1, 15, 3));
      expect(local.year, 2026);
      expect(local.month, 1);
      expect(local.day, 14);
      expect(local.hour, 23);
      expect(local.minute, 30);
    });
  });
}

StockMovementsService _serviceWithRows({
  required int totalRows,
  required List<Uri> requests,
  StockMovementsStoreTimezoneLoader? timezoneLoader,
}) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      requests.add(request.url);
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      final limit = int.parse(request.url.queryParameters['limit'] ?? '1000');
      final available = totalRows - offset;
      final count = available <= 0
          ? 0
          : available < limit
              ? available
              : limit;
      final rows = List<Map<String, dynamic>>.generate(
        count,
        (index) => _movementRow(offset + index),
      );
      return http.Response(
        jsonEncode(rows),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
  addTearDown(client.dispose);
  final service = StockMovementsService(
    supabase: client,
    tenantService: TenantService.testing(
      currentUserId: () => null,
      profileLookup: (_) async => const [],
    ),
    tenantIdLoader: () async => _tenantId,
    storeTimezoneLoader: timezoneLoader ?? (_) async => 'America/Santiago',
    enableRealtime: false,
  );
  addTearDown(service.dispose);
  return service;
}

http.Response _rowsResponse(
  List<Map<String, dynamic>> rows, {
  http.BaseRequest? request,
}) {
  return http.Response(
    jsonEncode(rows),
    200,
    headers: {'content-type': 'application/json'},
    request: request,
  );
}

Map<String, dynamic> _movementRow(int index, {String productId = _productId}) {
  return {
    'id': 'movement-$index',
    'product_id': productId,
    'product_name': 'Producto $index',
    'transaction_date': '2026-07-15T12:00:00Z',
    'movement_type': 'adjustment',
    'source': 'stock_adjustment',
    'quantity': 1,
    'stock_before': index,
    'stock_after': index + 1,
    'created_at': '2026-07-15T12:00:00Z',
  };
}
