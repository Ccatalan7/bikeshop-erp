import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/accounting/models/expense.dart';
import 'package:vinabike_erp/modules/accounting/services/expense_service.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_payment.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

// PostgREST runs with TimeZone = UTC: a timestamp without an offset is stored
// as if the device's wall clock were UTC. Bike history inserts carried their
// created_at that way (288 rows of bike_interventions 7 h early, 170 at 3 or
// 4 h on 2026-10-29); the stock adjustment, the purchase payment, the expense
// and the web order payment sent the user's time the same way.
final _offset = RegExp(r'(Z|[+-]\d{2}:\d{2})$');

const _tenant = '00000000-0000-4000-8000-000000000001';
const _bike = '00000000-0000-4000-8000-000000000b1c';

// Late in the evening, local: after 21:00 the UTC day is already tomorrow in
// Chile, so a missing offset also moves the day.
final _lateEvening = DateTime(2026, 10, 29, 23, 30);

void expectInstant(Object? value, DateTime expected, {required String field}) {
  expect(value, isA<String>(), reason: '$field must be sent');
  expect(
    value as String,
    matches(_offset),
    reason: '$field must carry its offset: without it PostgREST stores the '
        'wall clock as UTC',
  );
  expect(
    DateTime.parse(value).isAtSameMomentAs(expected),
    isTrue,
    reason: '$field must be the same instant the app meant',
  );
}

void main() {
  late List<http.Request> requests;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });

  late _RecordingDatabaseService database;
  late TenantService tenantService;

  setUp(() {
    requests = [];
    database = _RecordingDatabaseService();
    tenantService = TenantService.testing(
      currentUserId: () => null,
      profileLookup: (_) async => const <Map<String, dynamic>>[],
    );
  });

  group('bike history', () {
    test('an intervention insert carries offsets', () async {
      final service = BikeshopService(database, tenantService: tenantService);
      addTearDown(service.dispose);

      await service.createBikeIntervention(
        BikeIntervention(
          tenantId: _tenant,
          bikeId: _bike,
          systemKey: 'drivetrain',
          interventionType: BikeInterventionType.replacement,
          title: 'Cambio de cadena',
          performedAt: _lateEvening,
          createdAt: _lateEvening,
          updatedAt: _lateEvening,
        ),
      );

      final insert = database.single('bike_interventions');
      expectInstant(insert['performed_at'], _lateEvening,
          field: 'performed_at');
      expectInstant(insert['created_at'], _lateEvening, field: 'created_at');
    });

    test('a component lifecycle insert carries offsets', () async {
      final service = BikeshopService(database, tenantService: tenantService);
      addTearDown(service.dispose);
      final removedAt = _lateEvening.add(const Duration(days: 30));

      await service.createBikeComponentLifecycle(
        BikeComponentLifecycle(
          tenantId: _tenant,
          bikeId: _bike,
          systemKey: 'drivetrain',
          componentSlotKey: 'chain',
          componentLabel: 'Cadena KMC X11',
          status: BikeComponentLifecycleStatus.superseded,
          installedAt: _lateEvening,
          removedAt: removedAt,
          createdAt: _lateEvening,
          updatedAt: _lateEvening,
        ),
      );

      final insert = database.single('bike_component_lifecycles');
      expectInstant(insert['installed_at'], _lateEvening,
          field: 'installed_at');
      expectInstant(insert['removed_at'], removedAt, field: 'removed_at');
      expectInstant(insert['created_at'], _lateEvening, field: 'created_at');
    });

    test('the bike sheet sends purchase and warranty as calendar days', () {
      // `save_bike_aggregate` casts them `::date`; `.toUtc()` would move a
      // late purchase to the next day.
      final payload = BikeshopService.bikeAggregatePayload(
        Bike(
          id: _bike,
          tenantId: _tenant,
          customerId: '00000000-0000-4000-8000-0000000000c1',
          purchaseDate: _lateEvening,
          warrantyUntil: DateTime(2028, 10, 29),
        ),
      );

      expect(payload['purchase_date'], '2026-10-29');
      expect(payload['warranty_until'], '2028-10-29');
    });

    test('the profile sends last_confirmed_at as an instant', () {
      final profile = BikeProfile(
        tenantId: _tenant,
        bikeId: _bike,
        lastConfirmedAt: _lateEvening,
      );

      expectInstant(profile.toJson()['last_confirmed_at'], _lateEvening,
          field: 'last_confirmed_at');
    });
  });

  test('a stock adjustment sends its effective time as an instant', () async {
    database.stopAfterRpc = 'apply_inventory_stock_adjustment';
    final service = InventoryService(database, tenantService);

    await expectLater(
      service.applyStockAdjustment(
        productId: '00000000-0000-4000-8000-000000015125',
        quantity: 2,
        type: 'IN',
        reasonType: 'count_correction',
        effectiveAt: _lateEvening,
      ),
      throwsA(isA<_StopAfterWrite>()),
    );

    final params = database.rpcParams('apply_inventory_stock_adjustment');
    expectInstant(params['p_effective_at'], _lateEvening,
        field: 'p_effective_at');
  });

  test('a purchase payment sends its date as an instant', () async {
    database.stopAfterInsert = 'purchase_payments';
    final service = PurchaseService(database, tenantService);
    addTearDown(service.dispose);

    await expectLater(
      service.createPayment(
        PurchasePayment(
          tenantId: _tenant,
          invoiceId: '00000000-0000-4000-8000-0000000000a1',
          paymentMethodId: '00000000-0000-4000-8000-0000000000e1',
          amount: 25990,
          date: _lateEvening,
        ),
      ),
      throwsA(anything),
    );

    expectInstant(database.single('purchase_payments')['date'], _lateEvening,
        field: 'date');
  });

  test('a new expense sends issue and due dates as instants', () async {
    database.stopAfterInsert = 'expenses';
    final service = ExpenseService(database);
    addTearDown(service.dispose);
    final issueDate = DateTime(2026, 10, 1);
    final dueDate = DateTime(2026, 10, 31);

    await expectLater(
      service.saveExpense(
        Expense(
          tenantId: _tenant,
          expenseNumber: 'G-0001',
          issueDate: issueDate,
          dueDate: dueDate,
        ),
      ),
      throwsA(anything),
    );

    final insert = database.single('expenses');
    expectInstant(insert['issue_date'], issueDate, field: 'issue_date');
    expectInstant(insert['due_date'], dueDate, field: 'due_date');
  });

  test('confirming a web order payment sends its date as an instant', () async {
    String? rpcBody;
    final service = WebsiteService(
      supabase: SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/rpc/confirm_online_order_payment')) {
            rpcBody = request.body;
            return http.Response(
              '"00000000-0000-4000-8000-0000000000f1"',
              200,
              headers: const {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            '[]',
            200,
            headers: const {'content-type': 'application/json'},
            request: request,
          );
        }),
      ),
      tenantService: tenantService,
    );
    addTearDown(service.dispose);

    try {
      await service.confirmOrderPayment(
        '00000000-0000-4000-8000-0000000000d1',
        paymentDate: _lateEvening,
      );
    } catch (_) {
      // Only the write is under test; the reload afterwards needs a session.
    }

    expect(rpcBody, isNotNull, reason: 'the payment RPC must be called');
    final params = jsonDecode(rpcBody!) as Map<String, dynamic>;
    expectInstant(params['p_payment_date'], _lateEvening,
        field: 'p_payment_date');
  });
}

/// Thrown right after the write under test, so the reads that follow it
/// (and their own setup) stay out of the test.
class _StopAfterWrite implements Exception {
  const _StopAfterWrite();
}

class _RecordingDatabaseService extends DatabaseService {
  final inserts = <({String table, Map<String, dynamic> data})>[];
  final rpcs = <({String name, Map<String, dynamic> params})>[];
  String? stopAfterInsert;
  String? stopAfterRpc;

  Map<String, dynamic> single(String table) {
    final rows = inserts.where((insert) => insert.table == table).toList();
    expect(rows, hasLength(1), reason: 'one insert into $table');
    return rows.single.data;
  }

  Map<String, dynamic> rpcParams(String name) {
    final calls = rpcs.where((call) => call.name == name).toList();
    expect(calls, hasLength(1), reason: 'one call to $name');
    return calls.single.params;
  }

  @override
  Future<Map<String, dynamic>> insert(
    String table,
    Map<String, dynamic> data, {
    bool applyTimestamps = true,
    String? selectColumns,
  }) async {
    inserts.add((table: table, data: Map.of(data)));
    if (table == stopAfterInsert) throw const _StopAfterWrite();
    return {'id': '00000000-0000-4000-8000-0000000000ff', ...data};
  }

  @override
  Future<dynamic> rpc(String functionName,
      {Map<String, dynamic>? params}) async {
    rpcs.add((name: functionName, params: Map.of(params ?? const {})));
    if (functionName == stopAfterRpc) throw const _StopAfterWrite();
    return null;
  }

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
  }) async =>
      const [];
}
