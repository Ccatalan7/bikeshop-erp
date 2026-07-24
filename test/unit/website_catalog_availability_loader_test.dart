import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/services/website_catalog_availability_loader.dart';

void main() {
  test(
    'hydrates more than 1000 rows in safe batches and preserves set availability',
    () async {
      final ids = List.generate(
        1203,
        (index) =>
            '00000000-0000-0000-0000-${index.toString().padLeft(12, '0')}',
      );
      final setAvailability = <String, int>{
        ids[1200]: 2,
        ids[1201]: 4,
        ids[1202]: 3,
      };
      final requestedBatchSizes = <int>[];
      final loader = WebsiteCatalogAvailabilityLoader.forTesting(
        (tenantId, productIds) async {
          expect(tenantId, 'tenant-1');
          requestedBatchSizes.add(productIds.length);
          return productIds
              .map(
                (id) => {
                  'product_id': id,
                  'available_quantity': setAvailability[id] ?? 1,
                },
              )
              .toList(growable: false);
        },
      );
      final rows = [
        for (var index = 0; index < ids.length; index++)
          <String, dynamic>{
            'id': ids[index],
            'is_set': index >= 1200,
            'inventory_qty': index >= 1200 ? 0 : 1,
            'stock_quantity': index >= 1200 ? 0 : 1,
          },
      ];

      final availability = await loader.load(
        tenantId: 'tenant-1',
        productIds: ids,
      );
      WebsiteCatalogAvailabilityLoader.applyToRows(
        rows: rows,
        availabilityByProductId: availability,
      );

      expect(requestedBatchSizes, [500, 500, 203]);
      expect(availability.length, 1203);
      expect(rows.where((row) => (row['stock_quantity'] as int) > 0),
          hasLength(1203));
      expect(rows[1200]['stock_quantity'], 2);
      expect(rows[1201]['stock_quantity'], 4);
      expect(rows[1202]['stock_quantity'], 3);
    },
  );

  test('fails closed when a canonical availability batch is incomplete',
      () async {
    final loader = WebsiteCatalogAvailabilityLoader.forTesting(
      (_, productIds) async => [
        {
          'product_id': productIds.first,
          'available_quantity': 1,
        },
      ],
    );

    expect(
      () => loader.load(
        tenantId: 'tenant-1',
        productIds: const ['product-1', 'product-2'],
      ),
      throwsA(isA<StateError>()),
    );
  });
}
