import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'http://127.0.0.1:54321', anonKey: 'test-key');
  });

  late _Database database;
  late TenantService tenant;
  late PurchaseService service;
  String? userId;
  setUp(() {
    userId = null;
    database = _Database();
    tenant = TenantService.testing(
      currentUserId: () => userId,
      profileLookup: (_) async => [
        {'tenant_id': 'tenant-b'}
      ],
    );
    service = PurchaseService(database, tenant);
  });
  tearDown(() {
    service.dispose();
    database.dispose();
    tenant.dispose();
  });

  test('concurrent consumers wait for the same completed list', () async {
    final first = service.getPurchaseInvoicesForList();
    final second = service.getPurchaseInvoicesForList();
    var secondFinished = false;
    unawaited(second.then((_) => secondFinished = true));
    await Future<void>.delayed(Duration.zero);
    expect(database.calls, 1);
    expect(secondFinished, isFalse);
    expect(service.hasListInvoicesCache, isFalse);
    database.pending.complete([_invoice(6414)]);
    expect((await first).single.total, 6414);
    expect((await second).single.total, 6414);
    expect(service.isLoadingListInvoices, isFalse);
  });

  test('a successfully empty list is ready and is reused', () async {
    final first = service.getPurchaseInvoicesForList();
    database.pending.complete([]);
    expect(await first, isEmpty);
    expect(service.hasListInvoicesCache, isTrue);
    expect(await service.getPurchaseInvoicesForList(), isEmpty);
    expect(database.calls, 1);
  });

  test('failure reaches all waiting consumers and permits retry', () async {
    final first = service.getPurchaseInvoicesForList();
    final second = service.getPurchaseInvoicesForList();
    final checks = [
      expectLater(first, throwsA(isA<Exception>())),
      expectLater(second, throwsA(isA<Exception>())),
    ];
    database.pending.completeError(StateError('offline'));
    await Future.wait(checks);
    expect(service.isLoadingListInvoices, isFalse);
    expect(service.hasListInvoicesCache, isFalse);
    database.pending = Completer<List<Map<String, dynamic>>>();
    final retry = service.getPurchaseInvoicesForList();
    database.pending.complete([_invoice(42)]);
    expect((await retry).single.total, 42);
    expect(database.calls, 2);
  });

  test('a consumer arriving during refresh cannot adopt the old cache',
      () async {
    final first = service.getPurchaseInvoicesForList();
    database.pending.complete([_invoice(1)]);
    await first;
    database.pending = Completer<List<Map<String, dynamic>>>();
    final refresh = service.getPurchaseInvoicesForList(forceRefresh: true);
    final following = service.getPurchaseInvoicesForList();
    database.pending.complete([_invoice(2)]);
    expect((await refresh).single.total, 2);
    expect((await following).single.total, 2);
    expect(database.calls, 2);
  });

  test('a late list cannot publish after authority changes', () async {
    final first = service.getPurchaseInvoicesForList();
    final check =
        expectLater(first, throwsA(isA<AuthorityScopeChangedException>()));
    userId = 'user-b';
    await tenant.getTenantId();
    database.pending.complete([_invoice(1)]);
    await check;
    expect(service.hasListInvoicesCache, isFalse);
    expect(service.cachedListInvoices, isEmpty);
  });
}

Map<String, dynamic> _invoice(num total) => {
      'id': 'invoice-a',
      'tenant_id': 'tenant-a',
      'invoice_number': 'DOC-A',
      'supplier_id': 'supplier-a',
      'date': '2026-09-04',
      'status': 'draft',
      'total': total,
    };

class _Database extends DatabaseService {
  int calls = 0;
  var pending = Completer<List<Map<String, dynamic>>>();
  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String? selectColumns,
    String? where,
    List<String>? whereIn,
    String? orderBy,
    bool descending = false,
    int? limit,
    int? offset,
    bool fetchAll = false,
  }) {
    expect(table, 'purchase_invoice_list_read_model_v2');
    calls++;
    return pending.future;
  }
}
