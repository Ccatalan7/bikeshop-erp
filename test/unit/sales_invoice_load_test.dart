import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/accounting/services/accounting_service.dart';
import 'package:vinabike_erp/modules/sales/services/sales_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

class _Tenant extends TenantService {
  _Tenant()
      : super.testing(
          currentUserId: () => 'user-1',
          profileLookup: (_) async => const [],
        );

  @override
  Future<String?> getTenantId() async => 'tenant-1';
}

/// Cada lectura de facturas queda pendiente hasta que el test la responde.
class _Database extends DatabaseService {
  final reads = <Completer<List<Map<String, dynamic>>>>[];

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
    final read = Completer<List<Map<String, dynamic>>>();
    reads.add(read);
    return read.future;
  }
}

Map<String, dynamic> _invoice(String id, String number) => {
      'id': id,
      'tenant_id': 'tenant-1',
      'invoice_number': number,
      'date': '2026-10-03',
      'status': 'sent',
      'total': 10000,
      'paid_amount': 0,
      'balance': 10000,
    };

void main() {
  late _Database database;
  late SalesService sales;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
  });

  setUp(() {
    database = _Database();
    sales = SalesService(database, AccountingService(database), _Tenant());
  });

  tearDown(() => sales.dispose());

  test('a second caller waits for the read in progress, not an empty cache',
      () async {
    var secondDone = false;
    final first = sales.loadInvoices();
    final second = sales.loadInvoices().then((_) => secondDone = true);
    await pumpEventQueue();
    expect(database.reads, hasLength(1));
    expect(secondDone, isFalse);

    database.reads.single.complete([_invoice('a', 'FV-1')]);
    await Future.wait([first, second]);
    expect(
        sales.cachedInvoices.map((invoice) => invoice.invoiceNumber), ['FV-1']);
    expect(sales.invoiceError, isNull);
  });

  test('a forced refresh during a read reads again after it', () async {
    final first = sales.loadInvoices();
    await pumpEventQueue();
    final refresh = sales.loadInvoices(forceRefresh: true);
    database.reads.single.complete([_invoice('a', 'FV-1')]);
    await first;
    await pumpEventQueue();
    // La lectura vieja no basta: el refresco pide otra.
    expect(database.reads, hasLength(2));

    database.reads.last.complete([]);
    await refresh;
    expect(sales.cachedInvoices, isEmpty);
  });
}
