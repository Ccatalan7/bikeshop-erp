import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

// Un alta de cliente sin borrador (el diálogo del trabajo, la venta) no queda
// dos veces cuando se repite: con la conexión cortada, Karla Concha quedó seis
// veces en 25 s el 2026-10-30 (2026-11-25).

class _Tenant extends TenantService {
  _Tenant()
      : super.testing(
          currentUserId: () => 'user-1',
          profileLookup: (_) async => const [],
        );

  // Sin taller no se abre el canal en vivo ni se crea la fidelización.
  @override
  Future<String?> getTenantId() async => null;

  @override
  Map<String, dynamic> addTenantId(Map<String, dynamic> data) =>
      data..['tenant_id'] = 'tenant-1';
}

class _Database extends DatabaseService {
  final rows = <String, Map<String, dynamic>>{};
  final sentIds = <String>[];

  /// Las próximas altas llegan, pero su respuesta se pierde.
  int lostResponses = 0;

  /// Mientras no se completa, el alta queda en vuelo.
  Completer<void>? inFlight;

  /// El rechazo de la base para la próxima alta.
  Object? refusal;

  @override
  Future<IdentifiedInsert> insertIdentified(
    String table,
    Map<String, dynamic> data, {
    bool applyTimestamps = true,
    String? selectColumns,
    String? recordId,
  }) async {
    final id = recordId ?? 'sin-identidad-${sentIds.length}';
    sentIds.add(id);
    final gate = inFlight;
    if (gate != null) await gate.future;
    final refused = refusal;
    if (refused != null) {
      refusal = null;
      throw refused;
    }
    final existing = rows[id];
    if (existing != null) {
      return IdentifiedInsert(Map.of(existing), alreadySaved: true);
    }
    final now = DateTime.utc(2026, 11, 25).toIso8601String();
    rows[id] = {...data, 'id': id, 'created_at': now, 'updated_at': now};
    if (lostResponses > 0) {
      lostResponses--;
      throw const SocketException('Connection reset by peer');
    }
    return IdentifiedInsert(Map.of(rows[id]!));
  }

  @override
  Future<Map<String, dynamic>> update(
    String table,
    String id,
    Map<String, dynamic> data, {
    bool applyTimestamps = true,
    String? selectColumns,
  }) async {
    rows[id] = {...rows[id]!, ...data};
    return Map.of(rows[id]!);
  }

  @override
  Future<Map<String, dynamic>?> selectById(
    String table,
    String id, {
    String? selectColumns,
  }) async {
    final row = rows[id];
    return row == null ? null : Map.of(row);
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

Customer _customer(String name, String? phone, {String tenant = 'tenant-1'}) =>
    Customer(tenantId: tenant, name: name, rut: '', phone: phone);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'test-publishable-key',
      // Every call is answered by the fakes; nothing should reach the network.
      httpClient: MockClient((request) async => http.Response('[]', 500)),
    );
  });

  late _Database db;
  late CustomerService service;

  setUp(() {
    db = _Database();
    service = CustomerService(db, _Tenant());
  });

  group('the same customer typed again', () {
    test('a lost response and a second tap leave one customer', () async {
      db.lostResponses = 1;
      final karla = _customer('Karla Concha Gonzalez', '+56 9 5400 2018');

      await expectLater(
        service.createCustomer(karla),
        throwsA(isA<SocketException>()),
      );
      final second = await service.createCustomer(karla);

      expect(db.rows, hasLength(1));
      expect(db.sentIds, hasLength(2));
      expect(db.sentIds.toSet(), {second.id});
    });

    test('taps that cross wait for the same save', () async {
      db.inFlight = Completer<void>();
      final karla = _customer('Karla Concha Gonzalez', '+56954002018');

      final first = service.createCustomer(karla);
      final second = service.createCustomer(karla);
      final third = service.createCustomer(
        _customer('  karla  concha gonzalez ', '9 5400 2018'),
      );
      db.inFlight!.complete();
      final saved = await Future.wait([first, second, third]);

      expect(db.sentIds, hasLength(1));
      expect(saved.map((customer) => customer.id).toSet(), hasLength(1));
      expect(db.rows, hasLength(1));
    });

    test('after it is saved, a late tap returns the same customer', () async {
      final karla = _customer('Karla Concha Gonzalez', '+56954002018');

      final first = await service.createCustomer(karla);
      final late = await service.createCustomer(karla);

      expect(late.id, first.id);
      expect(db.rows, hasLength(1));
    });
  });

  group('another customer', () {
    test('another phone, another name or another shop is another create', () {
      final key = CustomerService.createIntentKey(
        _customer('Karla Concha Gonzalez', '+56 9 5400 2018'),
      );
      expect(
        CustomerService.createIntentKey(
          _customer(' KARLA concha  Gonzalez', '954002018'),
        ),
        key,
      );
      expect(
        CustomerService.createIntentKey(
          _customer('Karla Concha Gonzalez', '+56 9 5400 2019'),
        ),
        isNot(key),
      );
      expect(
        CustomerService.createIntentKey(
          _customer('Karla Concha', '+56 9 5400 2018'),
        ),
        isNot(key),
      );
      expect(
        CustomerService.createIntentKey(
          _customer('Karla Concha Gonzalez', '+56 9 5400 2018',
              tenant: 'tenant-2'),
        ),
        isNot(key),
      );
    });

    test('two people sharing a phone are two customers', () async {
      await service.createCustomer(_customer('Ana Pérez', '+56911112222'));
      await service.createCustomer(_customer('Tomás Pérez', '+56911112222'));

      expect(db.rows, hasLength(2));
    });

    test('a form identity wins over what was typed', () async {
      await service.createCustomer(
        _customer('Karla Concha Gonzalez', '+56954002018'),
        recordId: 'identidad-del-borrador',
      );

      expect(db.sentIds, ['identidad-del-borrador']);
    });
  });

  group('the database refusal', () {
    test('returns the customer that already exists', () async {
      db.rows['4feb7c70-78ae-46c6-8430-6a983879fa09'] = {
        'id': '4feb7c70-78ae-46c6-8430-6a983879fa09',
        'tenant_id': 'tenant-1',
        'name': 'Karla Concha Gonzalez',
        'rut': '',
        'phone': '+56954002018',
        'created_at': '2026-11-25T12:00:00Z',
        'updated_at': '2026-11-25T12:00:00Z',
      };
      db.refusal = const PostgrestException(
        message:
            'Este cliente ya se creó hace un momento: búscalo en la lista.',
        code: '23505',
        details: CustomerService.recentDuplicateDetail,
        hint: '4feb7c70-78ae-46c6-8430-6a983879fa09',
      );

      final customer = await service.createCustomer(
        _customer('Karla Concha Gonzalez', '+56954002018'),
      );

      expect(customer.id, '4feb7c70-78ae-46c6-8430-6a983879fa09');
      expect(db.rows, hasLength(1));
    });

    test('any other unique violation is still an error', () {
      expect(
        CustomerService.recentDuplicateOf(const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        )),
        isNull,
      );
      expect(
        CustomerService.recentDuplicateOf(const PostgrestException(
          message: 'x',
          code: '23503',
          details: CustomerService.recentDuplicateDetail,
          hint: '4feb7c70-78ae-46c6-8430-6a983879fa09',
        )),
        isNull,
      );
    });
  });
}
