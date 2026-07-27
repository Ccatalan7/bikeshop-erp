import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/services/public_product_snapshot_cache.dart';

void main() {
  group('PublicProductSnapshotCache', () {
    test('resolves the same tenant snapshot by id and normalized SKU', () {
      final cache = PublicProductSnapshotCache<String>();
      cache.put(
        tenantId: 'tenant-a',
        id: 'product-1',
        sku: ' ab-123 ',
        value: 'snapshot',
      );

      expect(
        cache.peekById(tenantId: 'tenant-a', id: 'product-1'),
        'snapshot',
      );
      expect(
        cache.peekBySku(tenantId: 'tenant-a', sku: 'AB-123'),
        'snapshot',
      );
      expect(
        cache.peekBySku(tenantId: 'tenant-b', sku: 'AB-123'),
        isNull,
      );
    });

    test('expires snapshots and removes their SKU aliases', () {
      var now = DateTime(2026, 7, 26, 12);
      final cache = PublicProductSnapshotCache<String>(
        maxAge: const Duration(seconds: 30),
        now: () => now,
      );
      cache.put(
        tenantId: 'tenant-a',
        id: 'product-1',
        sku: 'SKU-1',
        value: 'snapshot',
      );

      now = now.add(const Duration(seconds: 30));
      expect(
        cache.peekById(tenantId: 'tenant-a', id: 'product-1'),
        isNull,
      );
      expect(
        cache.peekBySku(tenantId: 'tenant-a', sku: 'SKU-1'),
        isNull,
      );
    });

    test('evicts least recently used snapshots and clears by tenant', () {
      final cache = PublicProductSnapshotCache<String>(maxEntries: 2);
      cache.put(
        tenantId: 'tenant-a',
        id: 'one',
        sku: 'ONE',
        value: 'one',
      );
      cache.put(
        tenantId: 'tenant-a',
        id: 'two',
        sku: 'TWO',
        value: 'two',
      );
      expect(cache.peekById(tenantId: 'tenant-a', id: 'one'), 'one');

      cache.put(
        tenantId: 'tenant-b',
        id: 'three',
        sku: 'THREE',
        value: 'three',
      );
      expect(cache.peekById(tenantId: 'tenant-a', id: 'two'), isNull);
      expect(cache.peekById(tenantId: 'tenant-a', id: 'one'), 'one');

      cache.clear(tenantId: 'tenant-a');
      expect(cache.peekById(tenantId: 'tenant-a', id: 'one'), isNull);
      expect(cache.peekById(tenantId: 'tenant-b', id: 'three'), 'three');
    });

    test('replacing a snapshot removes its previous SKU alias', () {
      final cache = PublicProductSnapshotCache<String>();
      cache.put(
        tenantId: 'tenant-a',
        id: 'product-1',
        sku: 'OLD',
        value: 'old',
      );
      cache.put(
        tenantId: 'tenant-a',
        id: 'product-1',
        sku: 'NEW',
        value: 'new',
      );

      expect(cache.peekBySku(tenantId: 'tenant-a', sku: 'OLD'), isNull);
      expect(cache.peekBySku(tenantId: 'tenant-a', sku: 'NEW'), 'new');
    });
  });
}
