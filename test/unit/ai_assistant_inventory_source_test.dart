import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

/// Drives the real inventory path of `sendMessage`.
///
/// The generic gate suite proves the rule; this one proves the wiring, on the
/// one capability the assistant actually uses all day. It exists because the
/// tool used to catch everything and hand back an error map, so a catalog read
/// that never completed and a catalog with nothing in it produced answers the
/// operator could not tell apart.
class _FakeInventoryService extends InventoryService {
  _FakeInventoryService(super.db, super.tenantService);

  Object? keywordFailure;
  List<Product> keywordResults = const <Product>[];

  @override
  Future<List<Product>> searchProductPreviews(
    String searchTerm, {
    int limit = 50,
  }) async {
    final failure = keywordFailure;
    if (failure != null) throw failure;
    return keywordResults;
  }

  @override
  Future<List<Map<String, dynamic>>> searchProductsSemantic(
    List<double> vector, {
    double threshold = 0.65,
    int limit = 10,
  }) async {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<Product?> getProductById(String id) async => null;
}

/// Keeps the suite offline.
///
/// The semantic leg is enrichment: with no embedding there is no vector, no
/// RPC and no proxy call, and the authoritative keyword read is exactly what
/// these tests are about. Leaving the real call in would make the suite depend
/// on a Gemini proxy over a dummy Supabase URL.
class _OfflineAIAssistantService extends AIAssistantService {
  @override
  Future<List<double>?> generateEmbedding(String text) async => null;
}

Product _product({
  required String id,
  required String tenantId,
  String name = 'CAMARA 29 X 1.75',
  int stock = 3,
}) {
  return Product(
    id: id,
    tenantId: tenantId,
    name: name,
    sku: 'SKU-$id',
    price: 7000,
    cost: 2800,
    inventoryQty: stock,
    isActive: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  late _FakeInventoryService inventory;
  late AIAssistantService service;

  final authority = AIAssistantTurnAuthority(
    ErpAuthorityScopeKey.from(userId: 'user-a', tenantId: 'tenant-a')!,
  );

  setUp(() {
    inventory = _FakeInventoryService(
      DatabaseService(),
      TenantService.testing(
        currentUserId: () => 'user-a',
        profileLookup: (_) async => const <Map<String, dynamic>>[],
      ),
    );
    service = _OfflineAIAssistantService();
    service.initialize();
  });

  Future<AIAssistantResponse> ask() {
    return service.sendMessage(
      'busca camara 29',
      inventoryService: inventory,
      authority: authority,
    );
  }

  test('a catalog read that failed is never reported as zero', () async {
    inventory.keywordFailure = StateError('connection reset');

    final response = await ask();

    expect(response.text, contains('no se pudo confirmar'));
    expect(response.text.toLowerCase(), isNot(contains('no encontré')));
    expect(response.text, isNot(contains('0 resultados')));
    expect(response.cards, isEmpty);
  });

  test('a product from another taller invalidates the whole search', () async {
    inventory.keywordResults = [
      _product(id: 'p1', tenantId: 'tenant-a'),
      _product(id: 'p2', tenantId: 'tenant-b'),
    ];

    final response = await ask();

    expect(response.text, contains('no se pudo confirmar'));
    expect(response.cards, isEmpty);
  });

  test('a product with no tenant invalidates the whole search', () async {
    inventory.keywordResults = [_product(id: 'p1', tenantId: '')];

    final response = await ask();

    expect(response.text, contains('no se pudo confirmar'));
    expect(response.cards, isEmpty);
  });

  test('a completed read with nothing in it is a real zero', () async {
    // The distinction the whole change exists for: this answer is allowed to
    // say it found nothing, because the catalog was actually read.
    inventory.keywordResults = const <Product>[];

    final response = await ask();

    expect(response.text, isNot(contains('no se pudo confirmar')));
  });

  test('a verified catalog answers with its own rows', () async {
    inventory.keywordResults = [
      _product(id: 'p1', tenantId: 'tenant-a'),
      _product(id: 'p2', tenantId: 'tenant-a', stock: 0),
    ];

    final response = await ask();

    expect(response.text, contains('Encontré 2 resultados'));
    expect(response.text, contains('1 de 2 aparecen con stock'));
    expect(response.cards, hasLength(2));
  });
}
