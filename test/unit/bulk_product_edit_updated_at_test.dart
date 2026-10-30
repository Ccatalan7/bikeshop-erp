import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/inventory/models/bulk_product_edit_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/services/bulk_product_edit_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';

// products.updated_at is timestamptz and no trigger stamps it. A timestamp
// without an offset is read in the session zone (UTC), so the device's wall
// clock was stored as UTC: an upload at 02:10 in Chile landed three hours
// behind now() on 2026-10-29.
final _offset = RegExp(r'(Z|[+-]\d{2}:\d{2})$');

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          // The image path uploads to Storage before writing the product.
          request.url.path.startsWith('/storage/v1/object/')
              ? '{"Key":"vinabike-assets/products/main/cadena.png"}'
              : '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
  });

  late _RecordingDatabaseService database;
  late BulkProductEditService service;
  late DateTime startedAt;

  setUp(() {
    database = _RecordingDatabaseService();
    service = BulkProductEditService(databaseService: database);
    startedAt = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
  });

  void expectUtcUpdatedAt() {
    expect(database.updates, hasLength(1));
    final update = database.updates.single;
    expect(update.table, 'products');
    expect(update.id, _productId);

    final updatedAt = update.data['updated_at'];
    expect(updatedAt, isA<String>());
    expect(
      updatedAt as String,
      matches(_offset),
      reason: 'updated_at must carry its offset: without it PostgREST '
          'stores the device wall clock as UTC',
    );
    final instant = DateTime.parse(updatedAt);
    expect(instant.isUtc, isTrue);
    expect(instant.isBefore(startedAt), isFalse);
    expect(
      instant.isAfter(DateTime.now().toUtc().add(const Duration(seconds: 1))),
      isFalse,
    );
  }

  test('classification payload sends updated_at in UTC', () async {
    final result = await service.applyClassification(
      products: [_product()],
      drafts: const {
        _productId: BulkClassificationRowDraft(
          productId: _productId,
          categoryId: 'category-chains',
          categoryName: 'Cadenas',
        ),
      },
    );

    expect(result.succeeded, 1);
    expectUtcUpdatedAt();
  });

  test('channels payload sends updated_at in UTC', () async {
    final result = await service.applyChannels(
      products: [_product()],
      drafts: const {
        _productId: BulkChannelsRowDraft(
          productId: _productId,
          website: false,
          googleMerchant: false,
          active: false,
        ),
      },
    );

    expect(result.succeeded, 1);
    expectUtcUpdatedAt();
  });

  test('pricing payload sends updated_at in UTC', () async {
    final result = await service.applyPricing(
      products: [_product()],
      drafts: const {
        _productId: BulkPricingRowDraft(
          productId: _productId,
          price: 21990,
          cost: 11000,
        ),
      },
    );

    expect(result.succeeded, 1);
    expectUtcUpdatedAt();
  });

  test('image payload sends updated_at in UTC', () async {
    final png =
        Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2)));

    final result = await service.applyImages(
      products: [_product()],
      assignments: {
        _productId: BulkImageAssignment(
          productId: _productId,
          file: BulkImageFile(name: 'cadena.png', bytes: png),
        ),
      },
      onlyWhenMissingImage: true,
    );

    expect(result.errors, isEmpty);
    expect(result.succeeded, 1);
    expectUtcUpdatedAt();
  });

  test('custom payload sends updated_at in UTC', () async {
    final result = await service.applyCustom(
      products: [_product()],
      enabledProductIds: const {_productId},
      fields: const [
        BulkCustomProductFieldDefinition(
          key: 'name',
          label: 'Nombre del producto',
          group: BulkCustomProductFieldGroup.identity,
          type: BulkCustomProductFieldType.text,
          isRequired: true,
          allowClear: false,
        ),
      ],
      rowValues: const {
        _productId: {'name': 'Cadena KMC X11 116 eslabones'},
      },
      categoryNamesById: const {},
      brandNamesById: const {},
      supplierNamesById: const {},
    );

    expect(result.errors, isEmpty);
    expect(result.succeeded, 1);
    expectUtcUpdatedAt();
  });
}

const _productId = '00000000-0000-4000-8000-000000015125';

// Unpublished, so the channel and custom paths do not stop on the tax check.
Product _product() => Product(
      id: _productId,
      tenantId: '00000000-0000-4000-8000-000000000001',
      name: 'Cadena KMC X11',
      sku: '15125',
      price: 19990,
      cost: 9990,
      isPublished: false,
    );

class _RecordingDatabaseService extends DatabaseService {
  final updates = <({String table, String id, Map<String, dynamic> data})>[];

  @override
  Future<Map<String, dynamic>> update(
    String table,
    String id,
    Map<String, dynamic> data, {
    bool applyTimestamps = true,
    String? selectColumns,
  }) async {
    updates.add((table: table, id: id, data: Map.of(data)));
    return {'id': id, ...data};
  }
}
