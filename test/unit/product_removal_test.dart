import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/inventory/models/product_removal.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart';
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

class _Database extends DatabaseService {
  _Database(this.response);

  final Object? response;
  final calls = <({String name, Map<String, dynamic>? params})>[];

  @override
  Future<dynamic> rpc(String functionName,
      {Map<String, dynamic>? params}) async {
    calls.add((name: functionName, params: params));
    return response;
  }

  final selects = <({String table, String? where})>[];

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
  }) async {
    selects.add((table: table, where: where));
    return const [];
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      // Every call is answered by the fakes; nothing should reach the network.
      httpClient: MockClient((request) async => http.Response('[]', 500)),
    );
  });

  group('ProductRemoval', () {
    test('reads a deleted product', () {
      final removal = ProductRemoval.fromRpc(
        {'outcome': 'deleted', 'reasons': <Object?>[]},
      );

      expect(removal.archived, isFalse);
      expect(removal.message(name: 'Cadena', isService: false),
          'Producto eliminado');
      expect(removal.message(name: 'Mantención', isService: true),
          'Servicio eliminado');
    });

    test('an archived product says what history it keeps', () {
      final removal = ProductRemoval.fromRpc({
        'outcome': 'archived',
        'reasons': ['ventas', 'movimientos de stock', 'registro de IVA'],
      });

      expect(removal.archived, isTrue);
      expect(
        removal.message(name: 'Cadena KMC X9', isService: false),
        'No se borró «Cadena KMC X9» porque tiene ventas, movimientos de '
        'stock y registro de IVA: quedó inactivo y esa historia se conserva.',
      );
    });

    test('one reason reads alone, and none still archives', () {
      expect(
        ProductRemoval.fromRpc({
          'outcome': 'archived',
          'reasons': ['trabajos'],
        }).message(name: 'Mantención', isService: true),
        'No se borró «Mantención» porque tiene trabajos: quedó inactivo y '
        'esa historia se conserva.',
      );
      expect(
        ProductRemoval.fromRpc({'outcome': 'archived'})
            .message(name: 'Tubo', isService: false),
        'No se borró «Tubo» porque tiene historia: quedó inactivo y esa '
        'historia se conserva.',
      );
    });

    test('the dialog says both outcomes before confirming', () {
      expect(
        ProductRemoval.confirmation('Piola de Cambio'),
        'Si «Piola de Cambio» no tiene historia, se borra para siempre. Si '
        'tiene ventas, compras, movimientos de stock o trabajos, queda '
        'inactivo y esa historia se conserva.',
      );
    });

    test('an unknown answer is an error, never a silent delete', () {
      expect(() => ProductRemoval.fromRpc(null), throwsFormatException);
      expect(() => ProductRemoval.fromRpc({'outcome': 'gone'}),
          throwsFormatException);
    });
  });

  test('removeProduct asks the base within the shop', () async {
    final db = _Database({
      'outcome': 'archived',
      'reasons': ['compras'],
    });
    final service = InventoryService(db, _Tenant());

    final removal = await service.removeProduct('product-1');

    expect(removal.archived, isTrue);
    expect(removal.reasons, ['compras']);
    expect(db.calls, hasLength(1));
    expect(db.calls.single.name, 'delete_or_archive_product_v1');
    expect(db.calls.single.params,
        {'p_tenant_id': 'tenant-1', 'p_product_id': 'product-1'});
  });

  test('a set reads only its components, not the whole catalog', () async {
    final db = _Database(null);
    final service = InventoryService(db, _Tenant());

    expect(await service.getSetComponents('set-1'), isEmpty);
    expect(db.selects.single.table, 'products');
    expect(db.selects.single.where, 'parent_set_id=set-1');
  });
}
